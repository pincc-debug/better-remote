import AppKit
import Darwin
import RemoteFitCore

// Event scaling adapted from UU LightSlide, MIT; see THIRD_PARTY_NOTICES.md.
// All mutable state belongs to EventTapThread, including source caching and fractional movement.
final class UUNativeScroll: @unchecked Sendable {
    static let marker: Int64 = 0x4252_5553
    static let companionBundleID = "local.rixin.UUScrollHelper"
    struct Snapshot: Sendable {
        var running: Bool
        var adjusted: Int
    }
    private let thread = EventTapThread.shared
    private let sourceOverride: (@Sendable (CGEvent) -> Bool)?
    private let clock: @Sendable () -> TimeInterval
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accumulator = UUScrollAccumulator()
    private var percent = UUScrollScaling.defaultPercent
    private var reversed = false
    private var adjusted = 0
    private var sources: [Int32: (time: TimeInterval, matches: Bool)] = [:]

    init(sourceOverride: (@Sendable (CGEvent) -> Bool)? = nil,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.sourceOverride = sourceOverride
        self.clock = clock
    }

    var snapshot: Snapshot {
        thread.sync {
            Snapshot(running: self.tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
                     adjusted: self.adjusted)
        }
    }

    func setPercent(_ value: Int) {
        thread.sync {
            let value = UUScrollScaling.clampedPercent(value)
            guard self.percent != value else { return }
            self.percent = value
            self.accumulator.reset()
        }
    }

    /// 反转滚动方向. Applies to the same UU-sourced events as speed scaling, never to local input.
    func setReversed(_ value: Bool) {
        thread.sync {
            guard self.reversed != value else { return }
            self.reversed = value
            self.accumulator.reset()
        }
    }

    /// Both axes, all three delta representations (line, point, fixed-point). Phases, flags,
    /// location and routing stay untouched. Values are read before any write because Quartz
    /// may derive one representation from another on set.
    static func reverseAxes(_ event: CGEvent) {
        let lines: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2]
        let points: [CGEventField] = [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let lineValues = lines.map { event.getIntegerValueField($0) }
        let pointValues = points.map { event.getIntegerValueField($0) }
        let fixedValues = fixed.map { event.getDoubleValueField($0) }
        for (field, value) in zip(lines, lineValues) { event.setIntegerValueField(field, value: -value) }
        for (field, value) in zip(points, pointValues) { event.setIntegerValueField(field, value: -value) }
        for (field, value) in zip(fixed, fixedValues) { event.setDoubleValueField(field, value: -value) }
    }

    @discardableResult func start() -> Bool {
        thread.sync {
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true); return CGEvent.tapIsEnabled(tap: tap) }
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            guard let tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                    guard let info else { return Unmanaged.passUnretained(event) }
                    let owner = Unmanaged<UUNativeScroll>.fromOpaque(info).takeUnretainedValue()
                    return owner.handle(type, event) ? Unmanaged.passUnretained(event) : nil
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
            self.tap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(self.thread.runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return CGEvent.tapIsEnabled(tap: tap)
        }
    }

    func stop() {
        thread.sync {
            if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            if let source = self.runLoopSource { CFRunLoopRemoveSource(self.thread.runLoop, source, .commonModes) }
            self.tap = nil; self.runLoopSource = nil
            self.accumulator.reset(); self.sources.removeAll()
        }
    }

    private func isUU(_ event: CGEvent, at now: TimeInterval) -> Bool {
        if let sourceOverride { return sourceOverride(event) }
        let pid = Int32(clamping: event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0, pid != getpid() else { return false }
        if let cached = sources[pid], now - cached.time < 2 { return cached.matches }
        var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = proc_pidpath(pid, &bytes, UInt32(bytes.count))
        let path = size > 0 ? String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        let matches = UUScrollScaling.isUUExecutable(path)
        if sources.count > 64 { sources.removeAll() }
        sources[pid] = (now, matches)
        return matches
    }

    /// Tap-thread only. Returns false only for subpixel movement with no gesture boundary.
    /// Mutates the existing event to retain routing, modifiers, timestamp and gesture phases.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            accumulator.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard type == .scrollWheel else { return true }
        let now = clock()
        let marker = event.getIntegerValueField(.eventSourceUserData)
        let modified = !event.flags.intersection([.maskControl, .maskCommand, .maskAlternate]).isEmpty
        let scales = !modified && percent < 100
        guard marker != Self.marker, marker != UUTouchScroll.marker,
              scales || reversed, isUU(event, at: now) else {
            accumulator.reset()
            return true
        }
        if !scales {
            // Direction only: keep the original magnitudes (also for ⌘/⌃/⌥ zoom-style scrolls).
            accumulator.reset()
            Self.reverseAxes(event)
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            adjusted += 1
            return true
        }
        func pixels(_ point: CGEventField, _ fixed: CGEventField, _ line: CGEventField) -> Double {
            let p = Double(event.getIntegerValueField(point))
            if p != 0 { return p }
            let f = event.getDoubleValueField(fixed)
            // Quartz normally provides points even for line events; fallback is 10 px/line.
            return f != 0 ? f * 10 : Double(event.getIntegerValueField(line)) * 10
        }
        let sign: Double = reversed ? -1 : 1
        let x = sign * pixels(.scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventDeltaAxis2)
        let y = sign * pixels(.scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventDeltaAxis1)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if phase & 1 != 0 { accumulator.reset() }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let target = event.getIntegerValueField(.eventTargetUnixProcessID)
        let window = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
        let point = event.location
        let context = "\(pid):\(target):\(window):\(Int(point.x / 32)):\(Int(point.y / 32))"
        let delta = accumulator.scale(x: x, y: y, percent: percent, time: now, context: context)
        adjusted += 1
        if delta.x == 0 && delta.y == 0 && phase == 0 && momentum == 0 { return false }
        guard let canonical = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                      wheel1: delta.y, wheel2: delta.x, wheel3: 0) else { return true }
        for field: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3,
                                    .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3] {
            event.setIntegerValueField(field, value: canonical.getIntegerValueField(field))
        }
        for field: CGEventField in [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3] {
            event.setDoubleValueField(field, value: canonical.getDoubleValueField(field))
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        if phase & (4 | 8) != 0 || momentum & 4 != 0 { accumulator.reset() }
        return true
    }
}
