import Foundation

/// 连接时显示 / 未连接时显示. Three levels, not a boolean.
///
/// 工具条 expands the toolbar, 悬浮球 keeps only the collapsed ball, 不显示 hides both.
/// A virtual resolution that has not been restored forces at least the ball, so 不显示
/// cannot remove the on-screen way back to 还原本机.
public enum ToolbarVisibility: String, Codable, CaseIterable, Sendable {
    case toolbar
    case ball
    case hidden

    public var title: String {
        switch self {
        case .toolbar: "工具条"
        case .ball: "悬浮球"
        case .hidden: "不显示"
        }
    }

    /// Old 连接时显示 on → 工具条, off → 悬浮球.
    public static func migratedConnected(_ stored: Bool) -> Self { stored ? .toolbar : .ball }
    /// Old 未连接时显示 on → 工具条, off → 不显示. Off already meant fully hidden.
    public static func migratedDisconnected(_ stored: Bool) -> Self { stored ? .toolbar : .hidden }

    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K, connected: Bool) -> Self? {
        guard container.contains(key) else { return nil }
        if let level = try? container.decode(Self.self, forKey: key) { return level }
        if let flag = try? container.decode(Bool.self, forKey: key) {
            return connected ? migratedConnected(flag) : migratedDisconnected(flag)
        }
        return connected ? .toolbar : .hidden
    }
}

/// Which 桌面工具条 setting applies right now, and when it changes.
///
/// 连接时显示 applies while a remote session is connected, 未连接时显示 otherwise.
/// A disconnect only counts after `disconnectGrace` seconds; reconnecting inside that window is
/// treated as if the session never dropped, so the toolbar does not flicker.
/// The ball (收起) and the menu-bar 显示工具条 item are manual, temporary states: the next
/// context switch applies the settings again, except the unrestored-resolution ball which stays.
public struct ToolbarPresence: Equatable, Sendable {
    public enum Context: Equatable, Sendable { case disconnected, connected }
    public enum Surface: Equatable, Sendable { case hidden, ball, toolbar }
    public static let disconnectGrace: TimeInterval = 5

    public private(set) var context: Context = .disconnected
    /// Uptime at which a pending disconnect takes effect.
    public private(set) var disconnectDeadline: TimeInterval?

    public init() {}

    public static func level(_ context: Context, preferences: Preferences) -> ToolbarVisibility {
        switch context {
        case .connected: preferences.toolbarWhenConnected
        case .disconnected: preferences.toolbarWhenDisconnected
        }
    }

    /// 工具条 stays expanded. 悬浮球 stays a ball. 不显示 hides both unless a virtual
    /// resolution is still outstanding, in which case the ball remains.
    public static func surface(level: ToolbarVisibility, virtualResolutionOutstanding: Bool) -> Surface {
        switch level {
        case .toolbar: .toolbar
        case .ball: .ball
        case .hidden: virtualResolutionOutstanding ? .ball : .hidden
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
