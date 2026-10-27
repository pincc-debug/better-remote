import Foundation

/// Adaptive interval for the toolbar-overlap check: fast while windows change,
/// slower when idle, and paused briefly right after an app launches or activates.
public struct WorkspaceCheckSchedule: Equatable, Sendable {
    public static let active: TimeInterval = 0.25
    public static let idle: TimeInterval = 1.0
    /// Unchanged checks before slowing down (about 2 s at the active rate).
    public static let idleAfter = 8
    public static let launchPause: TimeInterval = 1.5

    public private(set) var unchangedCount = 0
    public private(set) var pausedUntil: TimeInterval = 0

    public init() {}

    public var interval: TimeInterval { unchangedCount >= Self.idleAfter ? Self.idle : Self.active }
    public func isPaused(now: TimeInterval) -> Bool { now < pausedUntil }
    public mutating func unchanged() { unchangedCount = min(unchangedCount + 1, Self.idleAfter) }
    public mutating func changed() { unchangedCount = 0 }
    /// After the pause the next check runs at the active rate.
    public mutating func pause(now: TimeInterval) { pausedUntil = now + Self.launchPause; unchangedCount = 0 }
}
