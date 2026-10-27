import AppKit
import ApplicationServices
import RemoteFitCore

@MainActor
final class ApplicationWindowCatalog {
    static let shared = ApplicationWindowCatalog()
    struct Window: Equatable, Sendable {
        let pid: pid_t
        let id: CGWindowID
        let frame: CGRect
    }
    private var cached: [Window]?
    private var checkedAt = -Double.infinity
    private var pending: Task<[Window], Never>?
    private let query: @Sendable () -> [Window]
    private let uptime: () -> TimeInterval

    init(query: @escaping @Sendable () -> [Window] = ApplicationWindowCatalog.readWindows,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.query = query
        self.uptime = uptime
    }

    /// Background consumers share an in-flight scan and a short-lived snapshot.
    /// Explicit target selection still requests a fresh list through visibleWindows.
    func snapshot() async -> [Window] {
        if let cached, uptime() - checkedAt < 0.2 { return cached }
        if let pending { return await pending.value }
        let query = query
        let scan = Task.detached(priority: .utility) { query() }
        pending = scan
        let windows = await scan.value
        cached = windows
        checkedAt = uptime()
        pending = nil
        return windows
    }

    func visibleWindows() -> [Window] { query() }


    nonisolated private static func readWindows() -> [Window] {
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let own = ProcessInfo.processInfo.processIdentifier
        var regular: [pid_t: Bool] = [:]
        return rows.compactMap { row in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32, pid != own,
                  let id = row[kCGWindowNumber as String] as? NSNumber,
                  let raw = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw),
                  ApplicationTargetPolicy.isUsableWindow(frame) else { return nil }
            let usable = regular[pid] ?? (NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular)
            regular[pid] = usable
            return usable ? Window(pid: pid, id: id.uint32Value, frame: frame) : nil
        }
    }

    func focusedWindowUsable(pid: pid_t) -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeDowncast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.04)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return ApplicationTargetPolicy.isUsableWindow(CGRect(origin: .zero, size: size))
    }
}
