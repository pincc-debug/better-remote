import Foundation

/// Panel hint after UU device identification retries are exhausted (or device has no preset).
public struct UUIdentifyHint: Equatable, Sendable {
    public enum Action: String, Sendable {
        case openAccessibility
        case retry
        case openSettings
    }

    public var message: String
    public var actionTitle: String?
    public var action: Action?

    public init(message: String, actionTitle: String? = nil, action: Action? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
}

public enum UUIdentifyHintBuilder {
    /// Builds an honest panel hint. Success with a usable preset returns nil.
    public static func build(
        status: String?,
        device: RemoteDevice?,
        deviceHasPreset: Bool,
        defaultResolutionEnabled: Bool,
        hasDefaultPreset: Bool,
        exhausted: Bool,
        deviceResolutionEnabled: Bool
    ) -> UUIdentifyHint? {
        if let device {
            guard deviceResolutionEnabled, !deviceHasPreset else { return nil }
            let name = device.name
            if defaultResolutionEnabled, hasDefaultPreset {
                return .init(
                    message: "已识别「\(name)」，还没设分辨率，先用默认",
                    actionTitle: "设置",
                    action: .openSettings
                )
            }
            return .init(
                message: "已识别「\(name)」，还没设分辨率",
                actionTitle: "设置",
                action: .openSettings
            )
        }

        guard exhausted, let status, !status.isEmpty else { return nil }

        switch status {
        case "permission_missing":
            return .init(
                message: "需要辅助功能权限才能识别设备",
                actionTitle: "去开启",
                action: .openAccessibility
            )
        case "app_missing":
            return .init(message: "打开 UU 远程后才能识别设备")
        default:
            if defaultResolutionEnabled, hasDefaultPreset {
                return .init(
                    message: "没认出这台设备，已用默认分辨率",
                    actionTitle: "重试",
                    action: .retry
                )
            }
            return .init(
                message: "没认出这台设备",
                actionTitle: "重试",
                action: .retry
            )
        }
    }
}
