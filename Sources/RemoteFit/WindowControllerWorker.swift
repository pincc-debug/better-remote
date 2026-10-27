import AppKit
import ApplicationServices
import RemoteFitCore

actor WindowControllerWorker {
    private struct RestoreEntry {
        let pid: pid_t
        let window: AXUIElement
        let frame: CGRect
        let maximized: CGRect
    }
    private var restoreEntries: [RestoreEntry] = []
    private(set) var performing = false
    private var automaticAdjustment = false
    private var frontmostPID: pid_t?
    private let logURL: URL

    init(logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteFit/WindowActions.log")) {
        self.logURL = logURL
    }

    func perform(_ action: FloatingAction, targetPID: pid_t?, screen: CGRect, screens: [CGRect], workspace: CGRect? = nil) async throws {
        guard !performing else { return }
        performing = true
        defer { performing = false }
        frontmostPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard AXIsProcessTrusted() else { throw FitError.message("请先授予辅助功能权限") }
        guard let pid = targetPID, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            throw FitError.message("找不到可操作的窗口")
        }
        log("request action=\(action.rawValue) app=\(app.bundleIdentifier ?? "unknown")")
        let window = try focusedWindow(pid: pid)
        await MainActor.run {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid { _ = app.activate() }
        }
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let axFrame = try? frame(of: window)
        let serverID = windowServerID(pid: pid, window: window, frame: axFrame ?? .null)
        let original = serverID.flatMap(windowServerFrame) ?? axFrame
        log("resolve app=\(app.bundleIdentifier ?? "unknown") axFrame=\(String(describing: axFrame)) serverFrame=\(String(describing: serverID.flatMap(windowServerFrame)))")
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        log("begin action=\(action.rawValue) app=\(app.bundleIdentifier ?? "unknown") window=\(CFHash(window)) frame=\(String(describing: original)) enhancedUI=\(String(describing: value("AXEnhancedUserInterface", of: application) as? Bool))")
        do {
            if let workspace, action == .maximizeWindow || action == .centerWindow {
                guard let original else { throw FitError.message("无法读取窗口位置") }
                let saved = validRestore(pid: pid, window: window, current: original)
                let restoring = action == .maximizeWindow && saved != nil
                let target = action == .maximizeWindow
                    ? saved.map { WindowLayout.frame($0.frame, in: workspace, placement: .moveToScreen) } ?? workspace
                    : WindowLayout.frame(original, in: workspace, placement: .center)
                if action == .maximizeWindow, saved == nil, WindowLayout.approximatelyEqual(original, workspace) {
                    // Already maximized outside our toggle: ask the application
                    // for its own restore instead of saving a no-op snapshot.
                    if let restored = try await toggleNativeZoom(window: window, application: application, app: app, original: original) {
                        let fitted = WindowLayout.frame(restored, in: workspace, placement: .moveToScreen)
                        try await setCompatibleFrame(fitted, window: window, application: application, serverID: serverID, allowsSizeRounding: true)
                    }
                } else {
                    log("workspace toggle restoring=\(restoring) target=\(target)")
                    try await setCompatibleFrame(target, window: window, application: application, serverID: serverID, allowsSizeRounding: true)
                    if action == .maximizeWindow { rememberRestore(window: window, pid: pid, original: original, applied: target, restoring: restoring) }
                }
            } else if action == .maximizeWindow {
                try await maximize(window: window, application: application, app: app, original: original, serverID: serverID, fallbackScreen: screen, screens: screens)
            } else if action == .centerWindow {
                guard let original else { throw FitError.message("无法读取窗口位置") }
                let target = WindowLayout.frame(original, in: screen, placement: .center)
                log("center target=\(target)")
                if !WindowLayout.approximatelyEqual(original, target) {
                    try await setCompatibleFrame(target, window: window, application: application, serverID: serverID, allowsSizeRounding: true)
                }
            }
            log("success frame=\(String(describing: try? frame(of: window)))")
        } catch {
            log("failure frame=\(String(describing: try? frame(of: window))) error=\(error.localizedDescription)")
            throw error
        }
    }

    /// Explicit layouts always set and verify the complete frame; never toggle native zoom.
    @discardableResult
    func place(_ target: CGRect, handle: WindowAXHandle, pid: pid_t, placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        let window = handle.element
        guard !performing else { throw FitError.message("窗口正在调整，请稍后重试") }
        performing = true
        defer { performing = false }
        frontmostPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        let original = try frame(of: window)
        let serverID = windowServerID(pid: pid, window: window, frame: original)
        return try await setCompatibleFrame(target, window: window, application: application, serverID: serverID,
                                            allowsSizeRounding: true, placementArea: placementArea)
    }

    func moveAsideFromToolbar(_ candidate: ApplicationWindowCatalog.Window, toolbar: CGRect, screen: CGRect, side: ToolbarSide) async {
        guard !Task.isCancelled, !performing, AXIsProcessTrusted(),
              NSEvent.pressedMouseButtons == 0 else { return }
        performing = true
        automaticAdjustment = true
        defer { performing = false; automaticAdjustment = false }
        frontmostPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let app = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for window in value(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? [] {
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            AXUIElementSetMessagingTimeout(window, 0.2)
            guard (value("AXFullScreen", of: window) as? Bool) != true,
                  (value(kAXMinimizedAttribute, of: window) as? Bool) != true,
                  (value(kAXSubroleAttribute, of: window) as? String) == kAXStandardWindowSubrole,
                  let original = try? frame(of: window),
                  windowServerID(pid: candidate.pid, window: window, frame: original) == candidate.id,
                  WindowLayout.approximatelyEqual(original, candidate.frame),
                  let target = WindowLayout.avoidingToolbar(original, toolbar: toolbar, screen: screen, side: side) else { continue }
            if target.size != original.size {
                do {
                    try await setCompatibleFrame(target, window: window, application: app, serverID: candidate.id, allowsSizeRounding: true)
                    log("toolbar overlap trimmed appPID=\(candidate.pid) from=\(original) target=\(target)")
                } catch { log("toolbar overlap skipped appPID=\(candidate.pid) error=\(error.localizedDescription)") }
                return
            }
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success,
                  settable.boolValue else { return }
            var point = target.origin
            guard let position = AXValueCreate(.cgPoint, &point) else { return }
            // Intentionally write position once. Never invoke frame/size adjustment,
            // raise the window, activate its app, or retry after the user moves it.
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            log("toolbar overlap move appPID=\(candidate.pid) result=\(result.rawValue) from=\(original) target=\(target)")
            return
        }
    }

    func fillCollapsedToolbar(_ candidate: ApplicationWindowCatalog.Window, toolbar: CGRect, screen: CGRect, side: ToolbarSide) async {
        guard !Task.isCancelled, !performing, AXIsProcessTrusted(), NSEvent.pressedMouseButtons == 0 else { return }
        performing = true
        automaticAdjustment = true
        defer { performing = false; automaticAdjustment = false }
        frontmostPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let app = AXUIElementCreateApplication(candidate.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        for window in value(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? [] {
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            AXUIElementSetMessagingTimeout(window, 0.2)
            guard (value("AXFullScreen", of: window) as? Bool) != true,
                  (value(kAXMinimizedAttribute, of: window) as? Bool) != true,
                  (value(kAXSubroleAttribute, of: window) as? String) == kAXStandardWindowSubrole,
                  let original = try? frame(of: window),
                  windowServerID(pid: candidate.pid, window: window, frame: original) == candidate.id,
                  WindowLayout.approximatelyEqual(original, candidate.frame),
                  let target = WindowLayout.fillingCollapsedToolbar(original, toolbar: toolbar, screen: screen, side: side) else { continue }
            do {
                try await setCompatibleFrame(target, window: window, application: app, serverID: candidate.id, allowsSizeRounding: true)
                log("toolbar collapse filled appPID=\(candidate.pid) from=\(original) target=\(target)")
            } catch { log("toolbar collapse skipped appPID=\(candidate.pid) error=\(error.localizedDescription)") }
            return
        }
    }

    private func maximize(window: AXUIElement, application: AXUIElement, app: NSRunningApplication,
                          original: CGRect?, serverID: CGWindowID?, fallbackScreen: CGRect, screens: [CGRect]) async throws {
        guard (value("AXFullScreen", of: window) as? Bool) != true else { throw FitError.message("请先退出全屏") }
        restoreEntries.removeAll { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated != false }
        guard let original else {
            _ = try await toggleNativeZoom(window: window, application: application, app: app, original: nil)
            return
        }
        let saved = validRestore(pid: app.processIdentifier, window: window, current: original)
        let currentScreen = WindowLayout.screen(containing: original, screens: screens, fallback: fallbackScreen)
        let target = saved.map { WindowLayout.restoredFrame($0.frame, screens: screens, fallback: currentScreen) } ?? currentScreen
        if saved != nil {
            do {
                try await setCompatibleFrame(target, window: window, application: application, serverID: serverID, allowsSizeRounding: false)
                rememberRestore(window: window, pid: app.processIdentifier, original: original, applied: target, restoring: true)
                return
            } catch { log("saved-frame restore failed: \(error.localizedDescription); trying native zoom") }
        }
        if saved == nil, WindowLayout.reached(original, target: target, allowsSizeRounding: true) {
            // The window was filled outside this session; let its app restore it.
            _ = try await toggleNativeZoom(window: window, application: application, app: app, original: original)
            return
        }
        do {
            let actual = try await toggleNativeZoom(window: window, application: application, app: app, original: original)
            if let actual, WindowLayout.reached(actual, target: target, allowsSizeRounding: saved == nil) {
                rememberRestore(window: window, pid: app.processIdentifier, original: original, applied: target, restoring: saved != nil)
                return
            }
            log("native did not reach requested frame=\(target); trying geometry")
        } catch { log("native unavailable: \(error.localizedDescription); trying geometry") }
        do {
            try await setCompatibleFrame(target, window: window, application: application, serverID: serverID, allowsSizeRounding: saved == nil)
            rememberRestore(window: window, pid: app.processIdentifier, original: original, applied: target, restoring: saved != nil)
        } catch {
            let actual = serverID.flatMap(windowServerFrame) ?? (try? frame(of: window))
            if saved == nil, let actual, !WindowLayout.approximatelyEqual(actual, original) {
                rememberRestore(window: window, pid: app.processIdentifier, original: original, applied: actual, restoring: false)
            }
            throw error
        }
    }

    private func validRestore(pid: pid_t, window: AXUIElement, current: CGRect) -> RestoreEntry? {
        guard let entry = restoreEntries.first(where: { $0.pid == pid && CFEqual($0.window, window) }) else { return nil }
        guard WindowMaximizeSnapshot(original: entry.frame, maximized: entry.maximized).restoration(from: current) != nil else {
            restoreEntries.removeAll { $0.pid == pid && CFEqual($0.window, window) }
            log("discard stale restore current=\(current) saved=\(entry.frame) maximized=\(entry.maximized)")
            return nil
        }
        return entry
    }

    private func rememberRestore(window: AXUIElement, pid: pid_t, original: CGRect, applied: CGRect, restoring: Bool) {
        restoreEntries.removeAll { $0.pid == pid && CFEqual($0.window, window) }
        if !restoring, !WindowLayout.approximatelyEqual(original, applied) {
            restoreEntries.append(.init(pid: pid, window: window, frame: original, maximized: (try? frame(of: window)) ?? applied))
        }
        if restoreEntries.count > 50 { restoreEntries.removeFirst() }
    }

    @discardableResult
    private func setCompatibleFrame(_ target: CGRect, window: AXUIElement, application: AXUIElement,
                                    serverID: CGWindowID?, allowsSizeRounding: Bool,
                                    placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        let enhanced = (value("AXEnhancedUserInterface", of: application) as? Bool) == true
        let shouldSuspend = await MainActor.run { enhanced && !NSWorkspace.shared.isVoiceOverEnabled && !NSWorkspace.shared.isSwitchControlEnabled }
        let suspended = shouldSuspend && AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) == .success
        defer {
            if suspended {
                let result = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                log("restore enhancedUI result=\(result.rawValue)")
            }
        }
        log("geometry target=\(target) enhancedUISuspended=\(suspended)")
        return try await setFrame(target, of: window, serverID: serverID, allowsSizeRounding: allowsSizeRounding,
                                  placementArea: placementArea)
    }

    private func toggleNativeZoom(window: AXUIElement, application: AXUIElement,
                                  app: NSRunningApplication, original: CGRect?) async throws -> CGRect? {
        guard (value("AXFullScreen", of: window) as? Bool) != true else {
            throw FitError.message("请先退出全屏")
        }
        let control: AXUIElement
        let route: String
        // The Window > Zoom command invokes the app's native zoom/unzoom action.
        // In particular, Orca explicitly exposes Electron's `zoom` menu role.
        if let item = zoomMenuItem(of: application) {
            control = item
            route = "window-menu-zoom"
        } else if let raw = value(kAXZoomButtonAttribute, of: window),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let button = unsafeDowncast(raw, to: AXUIElement.self)
            // Never press a green fullscreen control as a substitute for Zoom.
            guard (value(kAXSubroleAttribute, of: button) as? String) == kAXZoomButtonSubrole else {
                throw FitError.message("该应用未提供窗口缩放操作")
            }
            control = button
            route = "native-zoom-button"
        } else {
            throw FitError.message("该应用未提供窗口缩放操作")
        }
        guard (value(kAXEnabledAttribute, of: control) as? Bool) != false else {
            throw FitError.message("当前窗口不能执行缩放")
        }
        let serverWindow = windowServerID(pid: app.processIdentifier, window: window, frame: original ?? .null)
        let before = serverWindow.flatMap(windowServerFrame) ?? original
        let activated = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier || app.activate()
        }
        guard activated else { throw FitError.message("无法切换到目标窗口") }
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        log("raise result=\(raised.rawValue)")
        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        log("native route=\(route) result=\(result.rawValue) serverWindow=\(String(describing: serverWindow)) before=\(String(describing: before))")
        guard result == .success else { throw FitError.message("无法执行窗口缩放") }
        guard let before else { log("native accepted without geometry readback"); return nil }
        let settled = try await WindowLayout.waitForNativeZoom(from: before) {
            if let id = serverWindow, let frame = self.windowServerFrame(id) { return frame }
            return try self.frame(of: window)
        }
        log("native settled=\(settled)")
        return settled
    }

    private func windowServerID(pid: pid_t, window: AXUIElement, frame: CGRect) -> CGWindowID? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates: [(CGWindowID, CGRect)] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return (number.uint32Value, rect)
        }
        let matches = candidates.filter { WindowLayout.approximatelyEqual($0.1, frame) }
        if matches.count == 1 { return matches[0].0 }
        if candidates.count == 1, (value(kAXMainAttribute, of: window) as? Bool) == true || frontmostPID == pid { return candidates[0].0 }
        return nil
    }

    private func windowServerFrame(_ id: CGWindowID) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let info = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }

    private func zoomMenuItem(of application: AXUIElement) -> AXUIElement? {
        guard let raw = value(kAXMenuBarAttribute, of: application), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let menuBar = unsafeDowncast(raw, to: AXUIElement.self)
        let windowNames = ["Window", "窗口", "視窗"]
        let zoomNames = ["Zoom", "缩放", "縮放"]
        for top in children(of: menuBar) where windowNames.contains(value(kAXTitleAttribute, of: top) as? String ?? "") {
            for menu in children(of: top) {
                for item in children(of: menu) where zoomNames.contains(value(kAXTitleAttribute, of: item) as? String ?? "") {
                    return item
                }
            }
        }
        return nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    private func log(_ message: String) {
        WindowActionLog.append(message, to: logURL)
    }

    private func focusedWindow(pid: pid_t) throws -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = value(attribute, of: app), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = unsafeDowncast(value, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(window, 0.5)
                if let frame = try? frame(of: window), ApplicationTargetPolicy.isUsableWindow(frame) { return window }
            }
        }
        if let list = value(kAXWindowsAttribute, of: app) as? [AXUIElement] {
            let windows = list.filter { window in
                guard let rect = try? frame(of: window) else { return false }
                return ApplicationTargetPolicy.isUsableWindow(rect)
            }
            if let selected = windows.first(where: { (value(kAXMainAttribute, of: $0) as? Bool) == true }) { return selected }
            if windows.count == 1 { return windows[0] }
        }
        throw FitError.message("找不到可操作的窗口")
    }

    private func value(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        guard let position = value(kAXPositionAttribute, of: window), CFGetTypeID(position) == AXValueGetTypeID(),
              let dimensions = value(kAXSizeAttribute, of: window), CFGetTypeID(dimensions) == AXValueGetTypeID() else {
            throw FitError.message("该窗口不支持调整")
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(dimensions, to: AXValue.self), .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            throw FitError.message("无法读取窗口位置")
        }
        return CGRect(origin: point, size: size)
    }

    private func checkSettable(_ target: CGRect, current: CGRect, window: AXUIElement) throws {
        if (value("AXFullScreen", of: window) as? Bool) == true { throw FitError.message("请先退出全屏") }
        for (attribute, needed) in [(kAXPositionAttribute, target.origin != current.origin),
                                    (kAXSizeAttribute, target.size != current.size)] where needed {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success, settable.boolValue else {
                throw FitError.message("该窗口不支持调整")
            }
        }
    }

    private func setFrame(_ target: CGRect, of window: AXUIElement, serverID: CGWindowID?, allowsSizeRounding: Bool = false,
                          placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        let current = try serverID.flatMap(windowServerFrame) ?? frame(of: window)
        try checkSettable(target, current: current, window: window)
        var point = target.origin
        var size = target.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else {
            throw FitError.message("无法调整窗口")
        }
        // Size, position, size: macOS may constrain the first resize at the old
        // origin. Await each stage so animated AX updates cannot overwrite it.
        for attempt in 0..<2 {
            for (attribute, value) in [(kAXSizeAttribute, dimensions), (kAXPositionAttribute, position), (kAXSizeAttribute, dimensions)] {
                try Task.checkCancellation()
                if automaticAdjustment, NSEvent.pressedMouseButtons != 0 { throw CancellationError() }
                let actual = try serverID.flatMap(windowServerFrame) ?? frame(of: window)
                if attribute == kAXSizeAttribute, actual.size == target.size { continue }
                if attribute == kAXPositionAttribute, actual.origin == target.origin { continue }
                try Task.checkCancellation()
                if automaticAdjustment, NSEvent.pressedMouseButtons != 0 { throw CancellationError() }
                let result = AXUIElementSetAttributeValue(window, attribute as CFString, value)
                log("write attempt=\(attempt) attribute=\(attribute) result=\(result.rawValue)")
                if result != .success { throw FitError.message("目标窗口不支持调整位置或尺寸") }
                try await Task.sleep(for: .milliseconds(80))
            }
            do {
                _ = try await WindowLayout.waitForFrame(target: target, allowsSizeRounding: allowsSizeRounding) {
                    if let id = serverID, let actual = self.windowServerFrame(id) { return actual }
                    return try self.frame(of: window)
                }
                return .placed
            } catch {
                try Task.checkCancellation()
                if attempt == 1 {
                    let actual = try serverID.flatMap(windowServerFrame) ?? frame(of: window)
                    if let placementArea, let constrained = WindowPlacement.constrainedFrame(actual, target: target, in: placementArea) {
                        log("geometry-limited requested=\(target) actual=\(actual) placed=\(constrained)")
                        _ = try await setFrame(constrained, of: window, serverID: serverID, allowsSizeRounding: true)
                        return .sizeLimited
                    }
                    throw error
                }
            }
        }
        throw FitError.message("窗口未完成调整，请重试")
    }
}

private enum WindowActionLog {
    private static let queue = DispatchQueue(label: "local.RemoteFit.window-actions", qos: .utility)
    static func append(_ message: String, to logURL: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 256_000 {
                let previous = logURL.deletingLastPathComponent().appendingPathComponent("WindowActions.previous.log")
                try? manager.removeItem(at: previous)
                try? manager.moveItem(at: logURL, to: previous)
            }
            if !manager.fileExists(atPath: logURL.path) { manager.createFile(atPath: logURL.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\(timestamp) \(message)\n".utf8))
        }
    }
}
