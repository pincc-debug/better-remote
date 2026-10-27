import Foundation

/// Which 桌面工具条 setting applies right now, and when it changes.
///
/// 远程连接时显示 applies while a remote session is connected, 未连接时显示 otherwise.
/// A disconnect only counts after `disconnectGrace` seconds; reconnecting inside that window is
/// treated as if the session never dropped, so the toolbar does not flicker.
/// ON means the expanded toolbar, OFF means fully hidden (no ball). The ball (收起) and the
/// menu-bar 显示工具条 item are manual, temporary states: the next context switch applies the settings again.
public struct ToolbarPresence: Equatable, Sendable {
    public enum Context: Equatable, Sendable { case disconnected, connected }
    public static let disconnectGrace: TimeInterval = 5

    public private(set) var context: Context = .disconnected
    /// Uptime at which a pending disconnect takes effect.
    public private(set) var disconnectDeadline: TimeInterval?

    public init() {}

    /// Whether the expanded toolbar should be on screen in `context`.
    public static func shows(_ context: Context, preferences: Preferences) -> Bool {
        switch context {
        case .connected: preferences.toolbarWhenConnected
        case .disconnected: preferences.toolbarWhenDisconnected
        }
    }

    /// A confirmed remote transition. Returns the context to apply now, or nil when nothing changes yet.
    public mutating func remoteChanged(connected: Bool, at now: TimeInterval) -> Context? {
        if connected {
            if disconnectDeadline != nil { disconnectDeadline = nil; return nil }
            guard context != .connected else { return nil }
            context = .connected
            return .connected
        }
        guard context == .connected, disconnectDeadline == nil else { return nil }
        disconnectDeadline = now + Self.disconnectGrace
        return nil
    }

    /// Call when `disconnectDeadline` passes. Returns `.disconnected` once the grace period is over.
    public mutating func tick(at now: TimeInterval) -> Context? {
        guard let deadline = disconnectDeadline, now >= deadline else { return nil }
        disconnectDeadline = nil
        context = .disconnected
        return .disconnected
    }

    /// Seconds until `tick` should run, if a disconnect is pending.
    public func delayUntilTick(at now: TimeInterval) -> TimeInterval? {
        disconnectDeadline.map { max(0, $0 - now) }
    }
}
