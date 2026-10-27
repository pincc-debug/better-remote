import AppKit
import ApplicationServices

/// Explicit local diagnostic. Reads existing AX objects only: no activation,
/// window creation, AX actions, credential access, or permission prompts.
@MainActor
enum UUSilentAccessibilityCheck {
    static func run(bundleID: String = "com.netease.uuremote") {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            print("Target not running; no launch attempted")
            return
        }
        func visibleWindows() -> Int {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return list.filter {
                ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0
            }.count
        }
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
        }
        let beforeFront = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let beforeWindows = visibleWindows()
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw)
        let windows = raw as? [AXUIElement] ?? []
        var visited = 0
        let deadline = Date().addingTimeInterval(5)
        var rows: [[String]] = []
        var roles: [String: Int] = [:]
        var connectionTexts = Set<String>()
        func walk(_ element: AXUIElement, depth: Int, row: Int?) {
            guard depth < 20, visited < 1200, Date() < deadline else { return }
            visited += 1
            let role = value(element, kAXRoleAttribute) as? String ?? "unknown"
            roles[role, default: 0] += 1
            if role == kAXStaticTextRole, let text = value(element, kAXValueAttribute) as? String,
               ["连接", "远程", "控制", "vivo", "iPhone", "iPad"].contains(where: { text.contains($0) }) {
                connectionTexts.insert(text)
            }
            var rowIndex = row
            if (value(element, kAXRoleAttribute) as? String) == kAXRowRole {
                rows.append([])
                rowIndex = rows.count - 1
            }
            if let rowIndex, let text = value(element, kAXValueAttribute) as? String, !text.isEmpty {
                rows[rowIndex].append(text)
            }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                walk(child, depth: depth + 1, row: rowIndex)
            }
        }
        for window in windows { walk(window, depth: 0, row: nil) }
        let result: [String: Any] = [
            "bundleID": bundleID, "roles": roles, "connectionTexts": connectionTexts.sorted(),
            "trusted": AXIsProcessTrusted(), "axStatus": status.rawValue,
            "axWindows": windows.count, "visited": visited,
            "beforeFrontPID": beforeFront, "afterFrontPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
            "beforeVisibleWindows": beforeWindows, "afterVisibleWindows": visibleWindows(),
            "controllerRows": rows.filter { $0.contains(where: { $0.contains("远程控制") }) }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
