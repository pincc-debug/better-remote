import Foundation

public enum ConfiguredOperation: Identifiable, Equatable, Sendable {
    case shortcut(NamedShortcut)
    case builtin(FloatingAction)

    public var id: String {
        switch self {
        case .shortcut(let shortcut): Self.shortcutID(shortcut.id)
        case .builtin(let action): "builtin:\(action.rawValue)"
        }
    }
    public static func shortcutID(_ id: String) -> String { "shortcut:\(id)" }
}

extension Preferences {
    /// One complete ordering, including disabled operations, shared by both UIs.
    public var orderedOperations: [ConfiguredOperation] {
        let available = namedShortcuts.map(ConfiguredOperation.shortcut) + FloatingAction.configurableActions.filter { $0 != .maximizeWindow || floatingActions.contains($0) }.map(ConfiguredOperation.builtin)
        let lookup = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return (operationOrder + available.map(\.id)).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return lookup[id]
        }
    }

    public var enabledOperations: [ConfiguredOperation] {
        orderedOperations.filter {
            switch $0 {
            case .shortcut(let shortcut): shortcut.enabled
            case .builtin(let action): floatingActions.contains(action)
            }
        }
    }

    public mutating func moveOperations(from offsets: IndexSet, to destination: Int) {
        let ids = orderedOperations.map(\.id)
        let indices = offsets.filter { ids.indices.contains($0) }
        guard !indices.isEmpty, (0...ids.count).contains(destination) else { return }
        let moved = indices.map { ids[$0] }
        let indexSet = Set(indices)
        var remaining = ids.enumerated().filter { !indexSet.contains($0.offset) }.map(\.element)
        let insertion = destination - indices.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: insertion)
        operationOrder = remaining
    }
}
