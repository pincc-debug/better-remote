import AppKit
import ApplicationServices
import RemoteFitCore

/// 远程时窗口自动铺满: event-driven, no polling. Listens for app activation (NSWorkspace) and, for the
/// frontmost app only, AX window-created / main- and focused-window-changed notifications; bursts are
/// coalesced into one check `debounce` after the last event.
@MainActor
final class AutoFillController {
    static let debounce: Duration = .milliseconds(350)
    /// Fills the given app's front window if the policy allows it.
    var perform: (pid_t) async -> Void = { _ in }
    /// False while a resolution switch or termination is in progress.
    var canFill: () -> Bool = { true }
    private(set) var enabled = false
    private var activationObserver: NSObjectProtocol?
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedPID: pid_t?
    private var pending: Task<Void, Never>?
    private static let notifications = [kAXWindowCreatedNotification, kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification]

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.applicationActivated(pid) }
            }
            applicationActivated(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        } else {
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
            activationObserver = nil
            stopObserving()
            pending?.cancel(); pending = nil
            WindowControlPerformer.resetAutoFill()
        }
    }

    private func applicationActivated(_ pid: pid_t?) {
        guard enabled, let pid, pid != getpid() else { return }
        observe(pid)
        trigger()
    }

    private func observe(_ pid: pid_t) {
        guard observedPID != pid else { return }
        stopObserving()
        guard AXIsProcessTrusted() else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<AutoFillController>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { controller.trigger() }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications { AXObserverAddNotification(created, app, name as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created; observedApp = app; observedPID = pid
    }

    private func stopObserving() {
        if let observer, let observedApp {
            for name in Self.notifications { AXObserverRemoveNotification(observer, observedApp, name as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil; observedApp = nil; observedPID = nil
    }

    private func trigger(attempt: Int = 0) {
        guard enabled else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self, !Task.isCancelled, enabled else { return }
            // Never fight a drag or resize in progress; look again once the mouse is up (bounded).
            if NSEvent.pressedMouseButtons != 0 || !canFill() {
                if attempt < 8 { trigger(attempt: attempt + 1) }
                return
            }
            guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != getpid() else { return }
            await perform(pid)
        }
    }
}
