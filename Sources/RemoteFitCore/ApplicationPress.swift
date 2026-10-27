import Foundation

/// A held or dragged gesture must never turn into a launch on release.
public struct ApplicationPress: Sendable {
    public static let previewDelay: TimeInterval = 0.45
    public private(set) var previewed = false
    public private(set) var cancelled = false

    public init() {}

    public mutating func update(elapsed: TimeInterval, distance: Double, inside: Bool) -> Bool {
        if !inside || distance > 10 { cancelled = true }
        guard !cancelled, !previewed, elapsed >= Self.previewDelay else { return false }
        previewed = true
        return true
    }

    public func shouldLaunch(inside: Bool) -> Bool {
        inside && !cancelled && !previewed
    }
}
