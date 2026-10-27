import AppKit
import ApplicationServices
import RemoteFitCore

@MainActor
final class ShortcutSender {
    private var releaseEvents: [ShortcutStroke] = []
    private var activeID: String?
    private var eventSource: CGEventSource?
    private var eventTap = CGEventTapLocation.cghidEventTap
    private let relay = ShortcutEventRelay()
    private var usesRelay = false
    private var pendingTap: Task<Void, Never>?
    private var tapEpoch = 0
    private let permissionCheck: (() -> Bool)?
    private let activationRequest: ((pid_t?) async throws -> Void)?
    private let eventSink: (([ShortcutStroke], CGEventTapLocation) -> Void)?
    private let cursorRecovery: ((pid_t?) -> Void)?
    private(set) var heldID: String?
    /// Last regular app that should receive keys, excluding this process.
    var targetPID: (() -> pid_t?)?
    var onChange: (String?) -> Void = { _ in }

    init(permissionCheck: (() -> Bool)? = nil,
         activationRequest: ((pid_t?) async throws -> Void)? = nil,
         eventSink: (([ShortcutStroke], CGEventTapLocation) -> Void)? = nil,
         cursorRecovery: ((pid_t?) -> Void)? = nil) {
        self.permissionCheck = permissionCheck
        self.activationRequest = activationRequest
        self.eventSink = eventSink
        self.cursorRecovery = cursorRecovery
    }

    func releaseHeld() {
        guard heldID != nil else { return }
        releaseAll()
    }

    func releaseAll() {
        tapEpoch += 1
        pendingTap?.cancel()
        pendingTap = nil
        clearHeldEvents()
    }

    private func clearHeldEvents() {
        post(releaseEvents); releaseEvents = []
        relay.finishWhenIdle()
        eventSource = nil
        activeID = nil
        heldID = nil; onChange(nil)
    }
    func tap(_ shortcut: NamedShortcut) throws {
        try press(shortcut)
        release(shortcut)
    }
    func press(_ shortcut: NamedShortcut) throws {
        releaseAll()
        try sendPress(shortcut, target: resolveTarget(), activate: true)
    }

    private func sendPress(_ shortcut: NamedShortcut, target: pid_t?, activate: Bool) throws {
        clearHeldEvents()
        guard shortcut.isValid else { throw FitError.message("快捷键无效") }
        let permitted: Bool
        if let permissionCheck { permitted = permissionCheck() }
        else {
            ShortcutPermissions.shared.refresh()
            permitted = AXIsProcessTrusted()
        }
        guard permitted else {
            if permissionCheck == nil { ShortcutPermissions.shared.prepare {} }
            throw FitError.message("请先完成辅助功能授权")
        }
        let plan = ShortcutEventPlan.strokes(for: shortcut.key)
        guard !plan.press.isEmpty else { throw FitError.message("快捷键无效") }
        // Complete clicks use private state and enter after session filters.
        // Modifier-only/held gestures retain HID delivery for low-level listeners.
        let modifierOnly = ShortcutEventPlan.mask(for: shortcut.key.code) != nil
        let isolatedClick = !activate && !modifierOnly
        usesRelay = isolatedClick
        eventTap = usesRelay ? .cgSessionEventTap : .cghidEventTap
        if usesRelay, eventSink == nil { relay.prepare() }
        eventSource = CGEventSource(stateID: isolatedClick ? .privateState : .hidSystemState)
        eventSource?.localEventsSuppressionInterval = 0
        releaseEvents = plan.release
        activeID = shortcut.id
        // Held gestures need keyDown immediately, before mouseUp.
        if activate { focus(target) }
        OperationDiagnostics.write("shortcut-down code=\(shortcut.key.code) modifiers=\(shortcut.key.modifiers) target=\(target ?? 0) front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) tap=\(eventTap.rawValue) isolated=\(isolatedClick)")
        post(plan.press)
        heldID = shortcut.id; onChange(shortcut.id)
    }

    func release(_ shortcut: NamedShortcut) {
        guard activeID == shortcut.id else { return }
        if heldID != nil {
            clearHeldEvents()
        }
    }

    func waitForPendingTap() async { await pendingTap?.value }

    func enqueueTap(_ shortcut: NamedShortcut, targetPID: pid_t? = nil) {
        let previous = pendingTap
        let target = targetPID ?? resolveTarget()
        let epoch = tapEpoch
        pendingTap = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, tapEpoch == epoch else { return }
            do {
                try await focusAndWait(target)
                guard !Task.isCancelled, tapEpoch == epoch else { return }
                try sendPress(shortcut, target: target, activate: false)
                await relay.waitUntilDelivered()
                guard !Task.isCancelled, tapEpoch == epoch else { return }
                // Give the receiver a real press interval instead of placing
                // down, up and modifier reset in the same run-loop turn.
                try await Task.sleep(for: .milliseconds(35))
                guard !Task.isCancelled, tapEpoch == epoch else { return }
                release(shortcut)
                await relay.waitUntilDelivered()
                if shortcut.key.code == 36, shortcut.key.modifiers == 0 {
                    // Text receivers hide the cursor on Return. UU direct touch
                    // can then retain the old pointer position. A stationary
                    // mouse move restores normal pointer visibility after input.
                    try await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, tapEpoch == epoch else { return }
                    if let cursorRecovery { cursorRecovery(target) }
                    else if eventSink == nil { Self.restoreCursorAfterReturn(target: target) }
                }
            } catch is CancellationError {
                // Closing/reconfiguring the toolbar cancels queued actions.
            } catch {
                OperationDiagnostics.write("shortcut-failed code=\(shortcut.key.code) target=\(target ?? 0) error=\(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    private func focusAndWait(_ pid: pid_t?) async throws {
        if let activationRequest { try await activationRequest(pid); return }
        guard let pid else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw FitError.message("找不到目标应用")
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
        NSApp.yieldActivation(to: app)
        _ = app.activate()
        let deadline = ContinuousClock.now + .milliseconds(300)
        repeat {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        throw FitError.message("目标应用未完成切换")
    }

    private static func restoreCursorAfterReturn(target: pid_t?) {
        // Never interfere with a new target, a drag, or a newer pointer position.
        guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target,
              NSEvent.pressedMouseButtons == 0,
              let location = CGEvent(source: nil)?.location,
              let event = cursorRecoveryEvent(at: location) else { return }
        event.post(tap: .cghidEventTap)
        OperationDiagnostics.write("return-cursor-recovery target=\(target) position=\(location)")
    }

    static func cursorRecoveryEvent(at location: CGPoint) -> CGEvent? {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: location, mouseButton: .left) else { return nil }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        return event
    }

    private func resolveTarget() -> pid_t? {
        if let targetPID { return targetPID() }
        let front = NSWorkspace.shared.frontmostApplication
        let own = ProcessInfo.processInfo.processIdentifier
        if let front, front.processIdentifier != own, front.activationPolicy == .regular, !front.isTerminated {
            return front.processIdentifier
        }
        return nil
    }

    private func focus(_ pid: pid_t?) {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
        _ = app.activate()
    }

    static func keyboardEvent(for stroke: ShortcutStroke, source: CGEventSource?) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.code, keyDown: stroke.down) else { return nil }
        // Quartz marks arrows/navigation/function keys and keypad keys at creation.
        // These are key-identity flags, not extra Fn presses. Dropping them breaks
        // symbolic hotkeys such as Control-Up and can change keypad semantics.
        let keyFlags: CGEventFlags = stroke.modifier ? [] : event.flags.intersection([.maskSecondaryFn, .maskNumericPad])
        if stroke.modifier { event.type = .flagsChanged }
        event.flags = CGEventFlags(rawValue: stroke.flags).union(keyFlags)
        return event
    }

    private func post(_ strokes: [ShortcutStroke]) {
        guard !strokes.isEmpty else { return }
        if let eventSink { eventSink(strokes, eventTap); return }
        var events: [CGEvent] = []
        for stroke in strokes {
            if let event = Self.keyboardEvent(for: stroke, source: eventSource) { events.append(event) }
        }
        if usesRelay { relay.post(events) }
        else { events.forEach { $0.post(tap: eventTap) } }
    }
}
