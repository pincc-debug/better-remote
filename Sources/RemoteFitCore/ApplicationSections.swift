import Foundation

/// The launcher shows one scrolling list: recent first, then running, then the rest.
/// An app appears only in the first section that claims it; empty sections are dropped.
public struct ApplicationSection: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case recent = "最近"
        case running = "运行中"
        case all = "全部"
    }
    public let kind: Kind
    public let identifiers: [String]
    public var title: String { kind.rawValue }

    public static func make(recent: [String], running: [String], all: [String]) -> [ApplicationSection] {
        var seen = Set<String>()
        func claim(_ ids: [String]) -> [String] { ids.filter { !$0.isEmpty && seen.insert($0).inserted } }
        return [
            ApplicationSection(kind: .recent, identifiers: claim(recent)),
            ApplicationSection(kind: .running, identifiers: claim(running)),
            ApplicationSection(kind: .all, identifiers: claim(all))
        ].filter { !$0.identifiers.isEmpty }
    }
}
