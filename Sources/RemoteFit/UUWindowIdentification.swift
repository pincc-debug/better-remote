import AppKit
import ApplicationServices
import RemoteFitCore

struct UUWindowInspection: Sendable {
    var permitted = true
    /// False when AX messaging timed out or otherwise failed while Accessibility is trusted.
    var axAvailable = true
    var hasWindow = false
    var devices: [RemoteDevice] = []
}

protocol UUWindowAccess: Sendable {
    func inspect() async -> UUWindowInspection
    func open() async -> Bool
    func minimize() async -> Bool
    func connected() async -> Bool
}

struct UUWindowReadResult: Sendable {
    var device: RemoteDevice?
    var status: String
    /// Nil when the existing window was left untouched.
    var minimized: Bool?
}

enum UUWindowIdentification {
    @MainActor
    static func identify() async -> UUWindowReadResult {
        guard AXIsProcessTrusted() else { return .init(status: "permission_missing") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.uuremote").first,
              let url = app.bundleURL else { return .init(status: "app_missing") }
        let result = await run(access: UUAXWindowAccess(pid: app.processIdentifier, url: url))
        OperationDiagnostics.write("uu-window status=\(result.status) identified=\(result.device != nil) minimized=\(result.minimized.map(String.init) ?? "skipped")")
        return result
    }

    /// Read existing windows without changing them. Only minimize windows opened
    /// for identification, including on cancellation. Cleanup never invalidates identity.
    static func run(access: any UUWindowAccess, timeout: TimeInterval = 8) async -> UUWindowReadResult {
        guard !Task.isCancelled, await access.connected() else { return .init(status: "disconnected") }
        var state = await access.inspect()
        // Single AX messaging timeout is ~0.5s; silent retries (≤2) at ~0.25s.
        var axRetries = 0
        while state.permitted, !state.axAvailable, axRetries < 2 {
            axRetries += 1
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { break }
            guard !Task.isCancelled, await access.connected() else { return .init(status: "disconnected") }
            state = await access.inspect()
        }
        guard state.permitted else { return .init(status: "permission_missing") }
        guard state.axAvailable else { return .init(status: "ax_unavailable") }
        let openedForIdentification = !state.hasWindow
        if openedForIdentification {
            guard await access.open() else { return .init(status: "open_failed") }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var device: RemoteDevice?
        var reason = "timeout"
        while !Task.isCancelled, Date() < deadline {
            guard await access.connected() else { reason = "disconnected"; break }
            if !state.axAvailable {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { break }
                state = await access.inspect()
                if !state.permitted { reason = "permission_missing"; break }
                continue
            }
            if !state.devices.isEmpty {
                if state.devices.count == 1 { device = state.devices[0]; reason = "read" }
                else { reason = "multiple_controllers" }
                break
            }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { break }
            state = await access.inspect()
            if !state.permitted { reason = "permission_missing"; break }
        }
        let minimized: Bool? = openedForIdentification ? await access.minimize() : nil
        if Task.isCancelled { return .init(status: "cancelled", minimized: minimized) }
        guard await access.connected() else { return .init(status: "disconnected", minimized: minimized) }
        return .init(device: device, status: reason, minimized: minimized)
    }
}

/// AX work is off the main actor and bounded. Window reopening goes through
/// LaunchServices; cleanup presses only the AX minimize button, never close.
private actor UUAXWindowAccess: UUWindowAccess {
    let pid: pid_t
    let url: URL
    private var mainWindows: [AXUIElement] = []

    init(pid: pid_t, url: URL) { self.pid = pid; self.url = url }

    func connected() -> Bool { RemoteSessionProbe.uuConnectedNow() }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }

    private func windows() -> [AXUIElement]? {
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success else { return nil }
        return raw as? [AXUIElement] ?? []
    }

    func inspect() -> UUWindowInspection {
        guard AXIsProcessTrusted() else { return .init(permitted: false, axAvailable: false) }
        guard let windows = windows() else { return .init(permitted: true, axAvailable: false) }
        var devices: [RemoteDevice] = []
        let deadline = Date().addingTimeInterval(1)
        var visited = 0
        for window in windows {
            var texts: [String] = []
            var rows: [[String]] = []
            var seen: [AXUIElement] = []
            func walk(_ element: AXUIElement, depth: Int, row: Int?) {
                guard depth < 22, visited < 1800, Date() < deadline,
                      !seen.contains(where: { CFEqual($0, element) }) else { return }
                seen.append(element)
                visited += 1
                var index = row
                if (attribute(element, kAXRoleAttribute) as? String) == kAXRowRole {
                    rows.append([]); index = rows.count - 1
                }
                if (attribute(element, kAXRoleAttribute) as? String) == kAXStaticTextRole,
                   let text = attribute(element, kAXValueAttribute) as? String, !text.isEmpty {
                    texts.append(text)
                    if let index { rows[index].append(text) }
                }
                for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                    walk(child, depth: depth + 1, row: index)
                }
            }
            walk(window, depth: 0, row: nil)
            let title = attribute(window, kAXTitleAttribute) as? String ?? ""
            let standard = (attribute(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole
            let isMain = texts.contains(where: { $0.contains("本机被控中") || $0 == "全部设备" })
                || (standard && (title.isEmpty || title == "UU远程"))
            if isMain {
                if !mainWindows.contains(where: { CFEqual($0, window) }) { mainWindows.append(window) }
                devices.append(contentsOf: rows.compactMap(UUWindowDeviceParser.device(in:)))
            }
        }
        return .init(hasWindow: !mainWindows.isEmpty, devices: devices)
    }

    func open() async -> Bool {
        let url = url
        do {
            try await Self.reopen(url)
            return true
        } catch { return false }
    }

    @MainActor
    private static func reopen(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func minimize() async -> Bool {
        // Reacquire once if opening was followed immediately by cancellation.
        if mainWindows.isEmpty { _ = inspect() }
        guard !mainWindows.isEmpty else { return false }
        for window in mainWindows {
            if (attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
            guard let raw = attribute(window, kAXMinimizeButtonAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
            let button = unsafeDowncast(raw, to: AXUIElement.self)
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return false }
        }
        for _ in 0..<8 {
            if mainWindows.allSatisfy({ (attribute($0, kAXMinimizedAttribute) as? Bool) == true }) { return true }
            // Cleanup must finish even when the connection task was cancelled.
            await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
        }
        return false
    }
}
