import Foundation

public struct ApplicationHistory: Sendable {
    public private(set) var recent: [Int32] = []
    public init() {}
    public mutating func activate(_ pid: Int32) {
        recent.removeAll { $0 == pid }
        recent.insert(pid, at: 0)
        if recent.count > 100 { recent.removeLast(recent.count - 100) }
    }
    public mutating func retain(_ live: Set<Int32>) { recent.removeAll { !live.contains($0) } }
    public func previous(excluding current: Int32?) -> Int32? { recent.first { $0 != current } }
}
