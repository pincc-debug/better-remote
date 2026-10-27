import AppKit
import Darwin
import RemoteFitCore

/// UU Remote only: a one-finger swipe (UU sends press + drag) scrolls at the
/// touch point with momentum, like a phone. Holding still ~0.4 s before moving
/// gives a real drag (select text, move windows); a quick tap still clicks.
/// Two-finger scrolling, ToDesk and local input are left untouched.
///
/// Thread confinement: every tap callback, timer and piece of gesture state lives on
/// `EventTapThread`; `start`/`stop`/`isRunning` hop there synchronously. Nothing here
/// touches the main thread, so main-thread work can never delay mouse input.
final class UUTouchScroll: @unchecked Sendable {
    private let thread = EventTapThread.shared
    private let sourceOverride: (@Sendable (CGEvent) -> Bool)?
    private let mouseSink: (@Sendable (CGEventType, CGPoint) -> Void)?
    private let pointerLocation: @Sendable () -> CGPoint?
    init(sourceOverride: (@Sendable (CGEvent) -> Bool)? = nil,
         mouseSink: (@Sendable (CGEventType, CGPoint) -> Void)? = nil,
         pointerLocation: @escaping @Sendable () -> CGPoint? = { CGEvent(source: nil)?.location }) {
        self.sourceOverride = sourceOverride
        self.mouseSink = mouseSink
        self.pointerLocation = pointerLocation
    }
    static let marker: Int64 = 0x5246_5343
    /// Thread-safe hit test against our own on-screen windows (CG global coordinates).
    var isOwnWindow: (CGPoint) -> Bool = UUTouchScroll.ownWindowContains
    var isRunning: Bool { thread.sync { self.tap != nil } }

    /// True only when the frontmost on-screen window under the point is ours.
    /// Matching any of our windows (e.g. Settings sitting behind the remote
    /// content) used to force passthrough drag across half the desktop.
    static func ownWindowContains(_ point: CGPoint) -> Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // CGWindowList is front-to-back; first frame that contains the point wins.
        for row in rows {
            guard let raw = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw),
                  frame.contains(point) else { continue }
            let alpha = (row[kCGWindowAlpha as String] as? CGFloat) ?? 1
            if alpha < 0.05 { continue }
            return (row[kCGWindowOwnerPID as String] as? Int32) == own
        }
        return false
    }

    private enum Phase {
        case idle
        case passthrough
        case pressed(start: CGPoint, time: TimeInterval)
        case scrolling(anchor: CGPoint, last: CGPoint)
    }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var phase = Phase.idle
    private var injectedPress = false
    private var gesture = ScrollGesture()
    private var holdTimer: Timer?
    private var momentumTimer: Timer?
    private var momentumFrames: [(dx: Double, dy: Double)] = []
    private var momentumAnchor = CGPoint.zero
    private var momentumGesture = ScrollGesture()
    private var momentumStarted = false
    private var lastClick: (time: TimeInterval, point: CGPoint, count: Int64)?
    private var uuProcesses: [Int64: Bool] = [:]
    private let eventSource = CGEventSource(stateID: .privateState)
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var trace: [String] = []
    private var traceStart: TimeInterval = 0
    private func record(_ type: CGEventType, _ event: CGEvent, _ action: String) {
        let names: [UInt32: String] = [1: "D", 2: "U", 6: "G", 5: "M"]
        if trace.isEmpty { traceStart = now }
        var name = names[type.rawValue] ?? "t\(type.rawValue)"
        if type == .scrollWheel {
            name = "S\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))/\(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))c\(event.getIntegerValueField(.scrollWheelEventIsContinuous))p\(event.getIntegerValueField(.scrollWheelEventScrollPhase))m\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))y\(Int(event.location.y))"
        }
        if trace.count < 40 { trace.append("\(name)@\(Int((now - traceStart) * 1000))\(action)") }
        if type == .leftMouseUp || trace.count >= 40 { flushTrace() }
    }
    private func flushTrace() {
        guard !trace.isEmpty else { return }
        OperationDiagnostics.write("uu-touch " + trace.joined(separator: " "))
        trace.removeAll()
    }

    @discardableResult
    func start() -> Bool { thread.sync { self.startOnTapThread() } }

    private func startOnTapThread() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // HID level so remote-client input is seen before session filters.
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = Unmanaged<UUTouchScroll>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            OperationDiagnostics.write("uu-touch-scroll-unavailable")
            return false
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(thread.runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        OperationDiagnostics.write("uu-touch-scroll-on")
        return true
    }

    func stop() { thread.sync { self.stopOnTapThread() } }

    private func stopOnTapThread() {
        let wasRunning = tap != nil || sessionTap != nil
        cancelGesture()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(thread.runLoop, runLoopSource, .commonModes) }
        tap = nil; runLoopSource = nil
        stopSessionTap()
        phase = .idle
        if wasRunning { OperationDiagnostics.write("uu-touch-scroll-off") }
    }

    private func cancelGesture(at point: CGPoint? = nil) {
        let current = point ?? pointerLocation()
        holdTimer?.invalidate(); holdTimer = nil
        if case .scrolling(let anchor, _) = phase { postScroll(dx: 0, dy: 0, at: current ?? anchor, phase: 4) }
        if let current { momentumAnchor = current }
        stopMomentum()
        if injectedPress {
            injectedPress = false
            if let point = current { postMouse(.leftMouseUp, at: point, clicks: 1) }
        }
        phase = .idle
        lastClick = nil
        gesture.reset()
    }

    private func isUU(_ event: CGEvent) -> Bool {
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard pid > 0 else { return false }
        if let known = uuProcesses[pid] { return known }
        var bytes = [CChar](repeating: 0, count: 4096)
        var result = false
        if proc_pidpath(pid_t(pid), &bytes, UInt32(bytes.count)) > 0 {
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result = path.contains("/UURemote.app/Contents/")
        }
        if uuProcesses.count > 64 { uuProcesses.removeAll() }
        uuProcesses[pid] = result
        return result
    }

    private var toDeskProcesses: [Int64: Bool] = [:]
    /// ToDesk injects at session level, so it is handled by a second tap there.
    private func isToDesk(_ event: CGEvent) -> Bool {
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard pid > 0 else { return false }
        if let known = toDeskProcesses[pid] { return known }
        var bytes = [CChar](repeating: 0, count: 4096)
        var result = false
        if proc_pidpath(pid_t(pid), &bytes, UInt32(bytes.count)) > 0 {
            let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result = path.contains("/ToDesk.app/") && path.hasSuffix("/ToDesk_Session")
        }
        if toDeskProcesses.count > 64 { toDeskProcesses.removeAll() }
        toDeskProcesses[pid] = result
        return result
    }
    private var sessionTap: CFMachPort?
    private var sessionSource: CFRunLoopSource?
    private var onSession = false
    private func startSessionTap(mask: CGEventMask) {
        guard sessionTap == nil else { return }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<UUTouchScroll>.fromOpaque(context).takeUnretainedValue()
                me.onSession = true
                defer { me.onSession = false }
                let consumed = me.handle(type, event)
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            OperationDiagnostics.write("todesk-touch-scroll-unavailable"); return
        }
        sessionTap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        sessionSource = source
        CFRunLoopAddSource(thread.runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        OperationDiagnostics.write("todesk-touch-scroll-on")
    }
    private func stopSessionTap() {
        if let sessionTap { CGEvent.tapEnable(tap: sessionTap, enable: false); CFMachPortInvalidate(sessionTap) }
        if let sessionSource { CFRunLoopRemoveSource(thread.runLoop, sessionSource, .commonModes) }
        sessionTap = nil; sessionSource = nil
    }
    /// HID tap handles UU only; session tap handles ToDesk only.
    private func isSource(_ event: CGEvent) -> Bool {
        if let sourceOverride { return sourceOverride(event) }
        return onSession ? isToDesk(event) : isUU(event)
    }

    /// Returns true when the event is consumed.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelGesture()
            OperationDiagnostics.write("uu-touch-tap-disabled session=\(onSession)")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if let sessionTap { CGEvent.tapEnable(tap: sessionTap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return false }
        if isSource(event) { return decide(type, event) }
        // Physical mouse input takes over immediately. Never replay an older
        // remote press, hold or momentum after the user returns to the Mac.
        if type == .mouseMoved || type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp {
            cancelGesture(at: event.location)
        }
        return false
    }

    private func decide(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return false }
        let location = event.location
        switch type {
        case .leftMouseDown:
            guard isSource(event) else { return false }
            finishScroll(momentum: false)
            stopMomentum()
            if isOwnWindow(location) { record(type, event, "own"); phase = .passthrough; return false }
            // ToDesk withholds the press until the finger moves, so a long press is
            // invisible here. Tap then press-and-drag is the drag gesture instead.
            if onSession, let last = lastClick, now - last.time < NSEvent.doubleClickInterval,
               hypot(location.x - last.point.x, location.y - last.point.y) < ScrollGesture.tapSlop * 3 {
                phase = .passthrough
                return false
            }
            phase = .pressed(start: location, time: now)
            scheduleHold()
            return true
        case .leftMouseDragged:
            switch phase {
            case .idle, .passthrough: return false
            case .pressed(let start, let time):
                let distance = hypot(location.x - start.x, location.y - start.y)
                switch TouchPressDecision.classify(elapsed: now - time, distance: distance) {
                case .undecided: record(type, event, "und"); return true
                case .hold:
                    record(type, event, "hold")
                    beginHold(at: start)
                    return false
                case .scroll:
                    record(type, event, "scr")
                    holdTimer?.invalidate(); holdTimer = nil
                    gesture.reset()
                    postScroll(dx: 0, dy: 0, at: start, phase: 1)
                    emit(from: start, to: location, anchor: start)
                    phase = .scrolling(anchor: start, last: location)
                    return true
                }
            case .scrolling(let anchor, let last):
                emit(from: last, to: location, anchor: anchor)
                phase = .scrolling(anchor: anchor, last: location)
                return true
            }
        case .mouseMoved:
            // UU keeps streaming moves while we own the gesture. If they pass
            // through, the cursor visibly drags even though we already switched
            // to scroll — swallow them and keep the pointer on the scroll anchor.
            switch phase {
            case .pressed(let start, _):
                warpPointer(to: start)
                return true
            case .scrolling(let anchor, _):
                warpPointer(to: anchor)
                return true
            case .idle, .passthrough:
                return false
            }
        case .leftMouseUp:
            switch phase {
            case .idle: return false
            case .passthrough:
                injectedPress = false
                phase = .idle
                flushTrace()
                return false
            case .pressed(let start, _):
                holdTimer?.invalidate(); holdTimer = nil
                phase = .idle
                // Click where the pointer is now when it is still within tap tolerance,
                // so a replayed tap never snaps the cursor back to the touch-down point.
                if let point = TouchPressDecision.replayPoint(start: start, current: pointerLocation() ?? location) {
                    record(type, event, "tap")
                    replayClick(at: point)
                } else {
                    record(type, event, "up")
                }
                return true
            case .scrolling:
                record(type, event, "scrup")
                finishScroll(momentum: true)
                return true
            }
        default:
            return false
        }
    }

    private func scheduleHold() {
        holdTimer?.invalidate()
        holdTimer = thread.timer(after: TouchPressDecision.holdDelay, repeats: false) { [weak self] in self?.holdElapsed() }
    }

    private func holdElapsed() {
        guard case .pressed(let start, _) = phase else { return }
        // Finger already moving → leave pressed; the next drag will become scroll.
        guard let current = pointerLocation(),
              hypot(current.x - start.x, current.y - start.y) < ScrollGesture.tapSlop else { return }
        OperationDiagnostics.write("uu-touch hold-timer")
        beginHold(at: start)
    }

    /// Long press: deliver the original press so following drags act natively.
    private func beginHold(at point: CGPoint) {
        holdTimer?.invalidate(); holdTimer = nil
        guard let current = pointerLocation(),
              let replay = TouchPressDecision.replayPoint(start: point, current: current) else {
            cancelGesture(); return
        }
        phase = .passthrough
        injectedPress = true
        postMouse(.leftMouseDown, at: replay, clicks: 1)
    }

    private func emit(from: CGPoint, to: CGPoint, anchor: CGPoint) {
        let delta = gesture.record(dx: to.x - from.x, dy: to.y - from.y, at: now)
        guard delta.vertical != 0 || delta.horizontal != 0 else { return }
        postScroll(dx: delta.horizontal, dy: delta.vertical, at: anchor, phase: 2)
    }

    private func finishScroll(momentum: Bool) {
        guard case .scrolling(let anchor, _) = phase else { return }
        phase = .idle
        postScroll(dx: 0, dy: 0, at: anchor, phase: 4)
        guard momentum else { return }
        let frames = ScrollGesture.momentum(velocity: gesture.velocity(at: now))
        guard !frames.isEmpty else { return }
        stopMomentum()
        momentumFrames = frames
        momentumAnchor = anchor
        momentumGesture.reset()
        momentumStarted = false
        momentumTimer = thread.timer(after: 1.0 / 60, repeats: true) { [weak self] in self?.momentumTick() }
    }

    private func momentumTick() {
        guard !momentumFrames.isEmpty else {
            postScroll(dx: 0, dy: 0, at: momentumAnchor, momentum: 3)
            momentumTimer?.invalidate(); momentumTimer = nil
            return
        }
        let frame = momentumFrames.removeFirst()
        let delta = momentumGesture.quantize(dx: frame.dx, dy: frame.dy)
        postScroll(dx: delta.horizontal, dy: delta.vertical, at: momentumAnchor, momentum: momentumStarted ? 2 : 1)
        momentumStarted = true
    }

    private func stopMomentum() {
        guard momentumTimer != nil else { return }
        momentumTimer?.invalidate(); momentumTimer = nil
        momentumFrames.removeAll()
        postScroll(dx: 0, dy: 0, at: momentumAnchor, momentum: 3)
    }

    private func postScroll(dx: Int32, dy: Int32, at point: CGPoint, phase: Int64 = 0, momentum: Int64 = 0) {
        guard let event = CGEvent(scrollWheelEvent2Source: eventSource, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if phase != 0 { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase) }
        if momentum != 0 { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum) }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    private func replayClick(at point: CGPoint) {
        var clicks: Int64 = 1
        if let last = lastClick, now - last.time < NSEvent.doubleClickInterval,
           hypot(point.x - last.point.x, point.y - last.point.y) < ScrollGesture.tapSlop * 2 {
            clicks = min(last.count + 1, 3)
        }
        lastClick = (now, point, clicks)
        postMouse(.leftMouseDown, at: point, clicks: clicks)
        postMouse(.leftMouseUp, at: point, clicks: clicks)
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint, clicks: Int64) {
        if let mouseSink { mouseSink(type, point); return }
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    private func warpPointer(to point: CGPoint) {
        // Marked so our own HID tap ignores the synthetic move.
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }
}
