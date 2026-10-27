import Foundation

public enum RemoteSoftware: String, Codable, CaseIterable, Sendable {
    case uu, toDesk, anyDesk
    public var title: String {
        switch self {
        case .uu: "UU 远程"
        case .toDesk: "ToDesk"
        case .anyDesk: "AnyDesk"
        }
    }
}

public struct RemoteSessionSnapshot: Equatable, Sendable {
    public var active: Set<RemoteSoftware>
    public var uuDevice: RemoteDevice?
    /// Last UU window identify status (e.g. read, permission_missing, ax_unavailable).
    public var uuIdentifyStatus: String?
    /// True after identify retries are exhausted without a device (panel may show a hint).
    public var uuIdentifyExhausted = false
    public var unknown: Set<RemoteSoftware>
    /// A pending vendor authorization can finish without another power notification.
    public var recheckAfter: TimeInterval?
    public init(active: Set<RemoteSoftware> = [], unknown: Set<RemoteSoftware> = []) {
        self.active = active
        self.unknown = unknown
    }

    public func confirmationDelay(_ stabilityDelay: TimeInterval?) -> TimeInterval? {
        [stabilityDelay, recheckAfter].compactMap { $0 }.min()
    }
}

/// A brief gap (or an unreadable sample) must not restore a live remote desktop.
public struct RemoteSessionStability: Sendable {
    public enum Transition: Equatable, Sendable { case connected, disconnected }
    public private(set) var isConnected = false
    private var candidateSince: TimeInterval?
    private var missingSince: TimeInterval?
    private var relevantProviders = Set<RemoteSoftware>()
    public init() {}

    /// Connected after this many continuous "active" seconds.
    public static let connectConfirm: TimeInterval = 2
    /// Disconnected after this many continuous "gone" seconds (phone kill → restore).
    public static let disconnectConfirm: TimeInterval = 1.5

    public func confirmationDelay(at now: TimeInterval) -> TimeInterval? {
        if let candidateSince { return max(0, candidateSince + Self.connectConfirm - now) }
        if let missingSince { return max(0, missingSince + Self.disconnectConfirm - now) }
        return nil
    }

    public mutating func observe(_ snapshot: RemoteSessionSnapshot, at now: TimeInterval) -> Transition? {
        if !snapshot.active.isEmpty {
            relevantProviders = snapshot.active.union(relevantProviders.intersection(snapshot.unknown))
            missingSince = nil
            guard !isConnected else { return nil }
            if candidateSince == nil { candidateSince = now }
            if now - (candidateSince ?? now) >= Self.connectConfirm {
                isConnected = true
                candidateSince = nil
                return .connected
            }
        } else if !snapshot.unknown.intersection(relevantProviders).isEmpty {
            candidateSince = nil
            missingSince = nil
        } else {
            candidateSince = nil
            guard isConnected else { return nil }
            if missingSince == nil { missingSince = now }
            if now - (missingSince ?? now) >= Self.disconnectConfirm {
                isConnected = false
                relevantProviders = []
                missingSince = nil
                return .disconnected
            }
        }
        return nil
    }
}

public struct RemotePowerAssertion: Sendable {
    public var executable: String
    public var type: String
    public var name: String
    public var level: Int
    public init(executable: String, type: String, name: String, level: Int) {
        self.executable = executable; self.type = type; self.name = name; self.level = level
    }
}

public enum RemoteSessionEvidence {
    /// Display-sleep assertion names UU holds only while a controller is connected
    /// (older builds, then 4.42+). "Disable Idle System Sleep" is resident and excluded.
    public static let uuConnectionAssertionNames: Set<String> = ["idleDisplaySleepDisabled", "UURemote Disable Display Sleep"]
    public static let toDeskConnectionAssertionName = "Preventing display sleep for app"
    public static let anyDeskAssertionName = "AnyDesk user using this computer remotely"

    public static func uuConnected(_ assertions: [RemotePowerAssertion]) -> Bool {
        assertions.contains {
            $0.executable.hasSuffix("/UURemote.app/Contents/Helpers/UURemoteServer") &&
            $0.type == "PreventUserIdleDisplaySleep" && uuConnectionAssertionNames.contains($0.name) && $0.level == 255
        }
    }

    public static func toDeskConnected(processes: Set<String>, assertions: [RemotePowerAssertion]) -> Bool {
        processes.contains { $0.hasSuffix("/ToDesk.app/Contents/Helpers/ToDesk_Session.app/Contents/MacOS/ToDesk_Session") } &&
        toDeskHasConnectionAssertion(assertions)
    }

    public static func toDeskHasConnectionAssertion(_ assertions: [RemotePowerAssertion]) -> Bool {
        assertions.contains {
            $0.executable.hasSuffix("/ToDesk.app/Contents/MacOS/ToDesk_Service") &&
            ["NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"].contains($0.type) &&
            $0.name == "Preventing display sleep for app" && $0.level == 255
        }
    }
}

/// Applies once per connection and restores the computer desktop on disconnection.
public struct AutomaticResolutionPolicy: Sendable {
    public enum Action: Equatable, Sendable { case apply, restore }
    public private(set) var enabled = false
    public private(set) var connected = false
    public private(set) var ownsResolution = false
    /// When false the remote resolution is kept after disconnection (for a computer only used remotely).
    public var restoreOnDisconnect = true
    private var manuallyAdjusted = false
    private var pendingApply = false
    private var pendingRestore = false
    private var pendingRelease = false
    public init() {}

    public mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { pendingRelease = false }
        pendingApply = value && connected
        if !value { ownsResolution = false }
    }
    public mutating func connectionChanged(_ value: Bool) {
        guard connected != value else { return }
        connected = value
        if value { manuallyAdjusted = false }
        pendingApply = value && enabled
        pendingRestore = !value && restoreOnDisconnect
    }
    public mutating func controllerChanged() {
        if enabled && connected && !manuallyAdjusted { pendingApply = true }
    }
    public mutating func nextAction(busy: Bool) -> Action? {
        guard !busy else { return nil }
        if pendingRelease {
            pendingRelease = false
            if ownsResolution && !manuallyAdjusted { return .restore }
        }
        if pendingRestore && !connected && restoreOnDisconnect { pendingRestore = false; return .restore }
        if enabled && pendingApply && connected { pendingApply = false; return .apply }
        return nil
    }
    public mutating func applied(success: Bool) {
        ownsResolution = success && (enabled || pendingRelease)
        pendingRestore = !connected && restoreOnDisconnect
    }
    public mutating func restored(success: Bool) {
        if success { ownsResolution = false }
    }
    /// A device opts out while connected. Restore only a resolution we applied,
    /// never a later manual adjustment; also handles an apply already in flight.
    public mutating func suspendConfiguration() {
        enabled = false
        pendingApply = false
        pendingRestore = false
        restoreOnDisconnect = false
        pendingRelease = !manuallyAdjusted
    }

    /// Changing the in-session resolution does not discard the pre-connection restore point.
    public mutating func manualAdjustment() {
        manuallyAdjusted = true
        pendingApply = false
        if !connected { manualOverride() }
    }
    public mutating func manualOverride() {
        pendingRelease = false
        manuallyAdjusted = true
        pendingApply = false
        pendingRestore = false
        ownsResolution = false
    }
}
