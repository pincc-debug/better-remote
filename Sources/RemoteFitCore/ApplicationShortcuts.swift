import Foundation

public struct ApplicationShortcuts: Codable, Identifiable, Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var path: String
    public var shortcuts: [NamedShortcut]
    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String, shortcuts: [NamedShortcut] = []) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.shortcuts = shortcuts
    }
    public var enabledShortcuts: [NamedShortcut] { shortcuts.filter { $0.enabled && $0.isValid } }

    /// Move to another pill's position; IDs outside this application are ignored.
    @discardableResult
    public mutating func moveShortcut(_ id: String, to targetID: String) -> Bool {
        guard id != targetID,
              let source = shortcuts.firstIndex(where: { $0.id == id }),
              let target = shortcuts.firstIndex(where: { $0.id == targetID }) else { return false }
        shortcuts.insert(shortcuts.remove(at: source), at: target)
        return true
    }
}

extension Preferences {
    public func applicationShortcuts(for bundleID: String?) -> ApplicationShortcuts? {
        guard applicationShortcutsEnabled, let bundleID else { return nil }
        return applicationShortcuts.first { $0.bundleID == bundleID && !$0.enabledShortcuts.isEmpty }
    }
}
