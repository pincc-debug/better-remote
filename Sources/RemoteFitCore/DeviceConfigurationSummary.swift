import Foundation

/// One-line card summary: only what differs from the default configuration.
public enum DeviceConfigurationSummary {
    public static let usesDefault = "使用默认"
    public static let defaultCard = "新设备沿用这套"

    public static func items(_ configuration: DeviceConfiguration, comparedTo base: DeviceConfiguration,
                             presetName: (String) -> String?) -> [String] {
        func onOff(_ value: Bool) -> String { value ? "开" : "关" }
        var items: [String] = []
        if configuration.selectedResolutionID != base.selectedResolutionID {
            let name = configuration.selectedResolutionID.map { presetName($0) ?? "自定义" } ?? "不切换"
            items.append("分辨率：\(name)")
        }
        if configuration.uuTouchScrollEnabled != base.uuTouchScrollEnabled {
            items.append("单指滚动：\(onOff(configuration.uuTouchScrollEnabled))")
        }
        if configuration.uuScrollSpeedPercent != base.uuScrollSpeedPercent {
            items.append("滚动速度：\(configuration.uuScrollSpeedPercent)%")
        }
        if configuration.remoteScrollReversed != base.remoteScrollReversed {
            items.append("反转滚动：\(onOff(configuration.remoteScrollReversed))")
        }
        if configuration.selectedResolutionID != nil, configuration.autoRestoreOnDisconnect != base.autoRestoreOnDisconnect {
            items.append("断开恢复：\(onOff(configuration.autoRestoreOnDisconnect))")
        }
        if configuration.autoFillWindowsOnRemote != base.autoFillWindowsOnRemote {
            items.append("窗口铺满：\(onOff(configuration.autoFillWindowsOnRemote))")
        }
        if configuration.toolbarWhenConnected != base.toolbarWhenConnected {
            items.append("工具条：\(onOff(configuration.toolbarWhenConnected))")
        } else if configuration.toolbarWhenConnected, configuration.toolbarSide != base.toolbarSide {
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
        let list = items(preferences.configuration(for: deviceID), comparedTo: preferences.configuration(for: nil)) { names[$0] }
        return list.isEmpty ? usesDefault : list.joined(separator: " · ")
    }
}
