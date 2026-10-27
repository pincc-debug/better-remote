import Foundation

/// Bundle identifiers in observed activation order, newest first.
public struct RecentApplications: Equatable, Sendable {
    public static let limit = 64
    public private(set) var identifiers: [String]

    public init(_ identifiers: [String] = []) {
        var seen = Set<String>()
        self.identifiers = Array(identifiers.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.limit))
    }

    public mutating func record(_ identifier: String) {
        guard !identifier.isEmpty else { return }
        identifiers.removeAll { $0 == identifier }
        identifiers.insert(identifier, at: 0)
        if identifiers.count > Self.limit { identifiers.removeLast(identifiers.count - Self.limit) }
    }

    public func available(in installed: Set<String>, limit: Int = 16) -> [String] {
        Array(identifiers.filter { installed.contains($0) }.prefix(max(0, limit)))
    }
}
