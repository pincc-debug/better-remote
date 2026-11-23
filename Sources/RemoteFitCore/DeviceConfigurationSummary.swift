import Foundation

/// One-line card summary: only what differs from the default configuration.
public enum DeviceConfigurationSummary {
    public static let usesDefault = "使用默认"
    public static let defaultCard = "新设备沿用这套"

    public static func items(_ configuration: DeviceConfiguration, comparedTo base: DeviceConfiguration,
                             software: RemoteSoftware? = nil, presetName: (String) -> String?) -> [String] {
        func onOff(_ value: Bool) -> String { value ? "开" : "关" }
        var items: [String] = []
        if configuration.selectedResolutionID != base.selectedResolutionID {
            let name = configuration.selectedResolutionID.map { presetName($0) ?? "自定义" } ?? "不切换"
            items.append("分辨率：\(name)")
        }
        if software?.supportsSingleFingerScroll != false, configuration.uuTouchScrollEnabled != base.uuTouchScrollEnabled {
            items.append("单指滚动：\(onOff(configuration.uuTouchScrollEnabled))")
        }
        if software?.supportsScrollSpeed != false, configuration.uuScrollSpeedPercent != base.uuScrollSpeedPercent {
            items.append("滚动速度：\(configuration.uuScrollSpeedPercent)%")
        }
        if software?.supportsScrollReversal != false, configuration.remoteScrollReversed != base.remoteScrollReversed {
            items.append("反转滚动：\(onOff(configuration.remoteScrollReversed))")
        }
        if configuration.selectedResolutionID != nil, configuration.autoRestoreOnDisconnect != base.autoRestoreOnDisconnect {
            items.append("断开恢复：\(onOff(configuration.autoRestoreOnDisconnect))")
        }
        if configuration.autoFillWindowsOnRemote != base.autoFillWindowsOnRemote {
            items.append("窗口铺满：\(onOff(configuration.autoFillWindowsOnRemote))")
        }
        if configuration.toolbarWhenConnected != base.toolbarWhenConnected {
            items.append("工具条：\(configuration.toolbarWhenConnected.title)")
        } else if configuration.toolbarWhenConnected == .toolbar, configuration.toolbarSide != base.toolbarSide {
            items.append("工具条：\(configuration.toolbarSide.title)")
        }
        if configuration.connectionDockMode != base.connectionDockMode {
            items.append("程序坞：\(configuration.connectionDockMode.title)")
        }
        return items
    }

    public static func text(for deviceID: String?, in preferences: Preferences) -> String {
        guard let deviceID else { return defaultCard }
        let names = Dictionary(preferences.customPresets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let list = items(preferences.configuration(for: deviceID), comparedTo: preferences.configuration(for: nil),
                         software: RemoteSoftware.savedDeviceSoftware(for: deviceID)) { names[$0] }
        return list.isEmpty ? usesDefault : list.joined(separator: " · ")
    }

    /// Readable summary of the default configuration itself (shown on the 默认配置 banner).
    public static func defaultSummary(in preferences: Preferences) -> String {
        effectiveSummary(for: nil, in: preferences)
    }

    /// Always describes what actually takes effect when this device (or default) connects,
    /// avoiding the misleading "使用默认" label for snapshotted device profiles.
    public static func effectiveSummary(for deviceID: String?, in preferences: Preferences) -> String {
        if let deviceID, !preferences.appliesConfiguration(for: deviceID) {
            return "已停用"
        }
        let configuration = preferences.configuration(for: deviceID)
        let software = deviceID.flatMap(RemoteSoftware.savedDeviceSoftware(for:))
        let names = Dictionary(preferences.customPresets.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var parts: [String] = []
        if let id = configuration.selectedResolutionID {
            parts.append(names[id] ?? "自定义分辨率")
        } else {
            parts.append("不切换分辨率")
        }
        if software?.supportsSingleFingerScroll != false, configuration.uuTouchScrollEnabled {
            parts.append("单指滚动")
        }
        if software?.supportsScrollSpeed != false, configuration.uuScrollSpeedPercent < 100 {
            parts.append("滚速 \(configuration.uuScrollSpeedPercent)%")
        }
        switch configuration.toolbarWhenConnected {
        case .toolbar: parts.append("显示工具条")
        case .ball: parts.append("悬浮球")
        case .hidden: parts.append("隐藏工具条")
        }
        return parts.joined(separator: " · ")
    }

    /// Names of saved devices (and/or 默认配置) currently bound to `presetID`.
    public static func users(of presetID: String, in preferences: Preferences) -> [String] {
        var result: [String] = []
        if preferences.configuration(for: nil).selectedResolutionID == presetID {
            result.append("默认配置")
        }
        for device in preferences.remoteDevices where device.appliesConfiguration {
            if preferences.configuration(for: device.id).selectedResolutionID == presetID {
                result.append(device.displayName)
            }
        }
        return result
    }
}
