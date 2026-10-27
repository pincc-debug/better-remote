import AppKit
import RemoteFitCore

/// Blocking cross-process queries run off the UI actor. AX handles never drive
/// our own NSWindows; those remain in WindowControlPerformer on the main actor.
actor WindowAXWorker {
    static let shared = WindowAXWorker()
    func perform(_ control: WindowControl, pid: pid_t) throws -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let window = targetWindow(app) else { throw FitError.message("没有可操作的窗口") }
        AXUIElementSetMessagingTimeout(window, 0.5)
        let close = button(kAXCloseButtonAttribute, of: window)
        let minimize = button(kAXMinimizeButtonAttribute, of: window)
        let zoom = button(kAXZoomButtonAttribute, of: window)
        let method = WindowControlTarget.method(
            for: control,
            hasCloseButton: element(kAXCloseButtonAttribute, of: window) != nil, hasMinimizeButton: minimize != nil,
            canSetMinimized: settable(kAXMinimizedAttribute, of: window),
            canSetFullScreen: settable("AXFullScreen", of: window),
            hasZoomButton: zoom != nil)
        OperationDiagnostics.write("window-control \(control.rawValue) pid=\(pid) method=\(method)")
        switch method {
        case .press(let attribute):
            let target = [kAXCloseButtonAttribute: close, kAXMinimizeButtonAttribute: minimize, kAXZoomButtonAttribute: zoom][attribute] ?? nil
            guard let target, AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
                throw FitError.message(control.unavailableMessage)
            }
        case .setMinimized:
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                throw FitError.message(control.unavailableMessage)
            }
        case .toggleFullScreen:
            let current = (value("AXFullScreen", of: window) as? Bool) ?? false
            let next: CFBoolean = current ? kCFBooleanFalse : kCFBooleanTrue
            guard AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, next) == .success else {
                if let zoom, AXUIElementPerformAction(zoom, kAXPressAction as CFString) == .success { return nil }
                throw FitError.message(control.unavailableMessage)
            }
        case .commandW:
            sendCommandW(to: pid)
        case .unavailable:
            throw FitError.message(control.unavailableMessage)
        }
        return nil
    }
    /// 清理桌面: minimizes the standard, non-full-screen windows of these apps (current Space only, as AX lists them).
    func minimizeAll(pids: [pid_t]) -> (minimized: Int, failed: Int) {
        var minimized = 0, failed = 0
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            guard let windows = value(kAXWindowsAttribute, of: app) as? [AXUIElement] else { continue }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.3)
                guard (value(kAXSubroleAttribute, of: window) as? String) == kAXStandardWindowSubrole as String,
                      (value(kAXMinimizedAttribute, of: window) as? Bool) != true,
                      (value("AXFullScreen", of: window) as? Bool) != true else { continue }
                if settable(kAXMinimizedAttribute, of: window),
                   AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                    minimized += 1
                } else if let button = button(kAXMinimizeButtonAttribute, of: window),
                          AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
                    minimized += 1
                } else {
                    failed += 1
                }
            }
        }
        return (minimized, failed)
    }
    private func targetWindow(_ app: AXUIElement) -> AXUIElement? {
        let focused = element(kAXFocusedWindowAttribute, of: app)
        let main = element(kAXMainWindowAttribute, of: app)
        var elements: [AXUIElement] = []
        for window in [focused, main].compactMap({ $0 }) + ((value(kAXWindowsAttribute, of: app) as? [AXUIElement]) ?? [])
            where !elements.contains(where: { CFEqual($0, window) }) {
            elements.append(window)
        }
        let flags = elements.map { window in
            (focused: focused.map { CFEqual($0, window) } ?? false, main: main.map { CFEqual($0, window) } ?? false)
        }
        let candidates = zip(elements, flags).map { window, flag in
            AXUIElementSetMessagingTimeout(window, 0.5)
            return WindowControlTarget.Candidate(
                focused: flag.focused, main: flag.main,
                minimized: (value(kAXMinimizedAttribute, of: window) as? Bool) ?? false,
                usable: frame(of: window).map(ApplicationTargetPolicy.isUsableWindow) ?? false)
        }
        return WindowControlTarget.select(candidates).map { elements[$0] }
    }

    func prepareSnap(pid: pid_t) async throws -> (WindowAXHandle, CGRect) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let window = targetWindow(app) else { throw FitError.message("没有可操作的窗口") }
        AXUIElementSetMessagingTimeout(window, 0.5)
        if (value("AXFullScreen", of: window) as? Bool) == true {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            try await Task.sleep(for: .milliseconds(900))
        }
        guard let current = frame(of: window) else { throw FitError.message("当前窗口不能调整位置") }
        guard settable(kAXPositionAttribute, of: window), settable(kAXSizeAttribute, of: window) else {
            throw FitError.message("当前窗口不能调整大小或位置")
        }
        return (WindowAXHandle(element: window), current)
    }

    /// The app's focused (else main) window with what 远程时窗口自动铺满 needs to judge it. Read-only.
    func autoFillProbe(pid: pid_t) -> (WindowAXHandle, AutoFillPolicy.Window)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let window = element(kAXFocusedWindowAttribute, of: app) ?? element(kAXMainWindowAttribute, of: app) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.5)
        let info = AutoFillPolicy.Window(
            role: value(kAXRoleAttribute, of: window) as? String,
            subrole: value(kAXSubroleAttribute, of: window) as? String,
            frame: frame(of: window),
            resizable: settable(kAXPositionAttribute, of: window) && settable(kAXSizeAttribute, of: window),
            fullScreen: (value("AXFullScreen", of: window) as? Bool) ?? false,
            minimized: (value(kAXMinimizedAttribute, of: window) as? Bool) ?? false,
            modal: (value(kAXModalAttribute, of: window) as? Bool) ?? false)
        return (WindowAXHandle(element: window), info)
    }

    func frontScreenWindow(pid: pid_t, windows: [ScreenWindow]) -> ScreenWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        if let window = targetWindow(app), let rect = frame(of: window),
           let match = windows.filter({ $0.pid == pid }).min(by: { distance(rect, $0.bounds) < distance(rect, $1.bounds) }),
           distance(rect, match.bounds) < 40 { return match }
        return windows.first { $0.pid == pid && $0.bounds.width >= 80 && $0.bounds.height >= 60 }
    }
    func resolve(_ item: ScreenWindow) -> WindowAXHandle? {
        let app = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let windows = (value(kAXWindowsAttribute, of: app) as? [AXUIElement]) ?? []
        let matches = windows.compactMap { window -> (AXUIElement, CGFloat)? in
            AXUIElementSetMessagingTimeout(window, 0.5)
            guard let rect = frame(of: window) else { return nil }
            return (window, distance(rect, item.bounds))
        }
        guard let match = matches.min(by: { $0.1 < $1.1 }), match.1 < 40 else { return nil }
        return WindowAXHandle(element: match.0)
    }
    private func distance(_ a: CGRect?, _ b: CGRect) -> CGFloat {
        guard let a else { return .greatestFiniteMagnitude }
        return abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    private func sendCommandW(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: down) else { continue }
            event.flags = .maskCommand
            event.postToPid(pid)
        }
    }

    private func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    private func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func button(_ attribute: String, of window: AXUIElement) -> AXUIElement? {
        guard let button = element(attribute, of: window) else { return nil }
        if let enabled = value(kAXEnabledAttribute, of: button) as? Bool, !enabled { return nil }
        return button
    }
    private func settable(_ attribute: String, of element: AXUIElement) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &result) == .success && result.boolValue
    }
    private func frame(of window: AXUIElement) -> CGRect? {
        guard let p = value(kAXPositionAttribute, of: window), let s = value(kAXSizeAttribute, of: window) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
