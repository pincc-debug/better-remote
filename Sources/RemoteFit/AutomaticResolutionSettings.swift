import SwiftUI
import RemoteFitCore

struct AutomaticResolutionSettings: View {
    @ObservedObject var model: ControlPanelModel
    @Environment(\.settingsNarrow) private var narrow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("分辨率") {
                VStack(spacing: 0) {
                    SettingsView.settingRow("连接时切换", symbol: "display.trianglebadge.exclamationmark") {
                        Toggle("连接时切换", isOn: Binding(
                            get: { model.preferences.autoResolutionEnabled },
                            set: { model.onAutoResolutionToggle($0) }
                        )).labelsHidden().toggleStyle(.switch)
                    }

                    if model.preferences.autoResolutionEnabled {
                        Text("优先按设备切换；未匹配时用默认，默认关闭则不切换。")
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, narrow ? 14 : 54)
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                        VStack(spacing: 0) {
                            Divider().padding(.leading, 54)

                            SettingsView.settingRow("按设备切换", symbol: "ipad.and.iphone") {
                                Toggle("按设备切换", isOn: Binding(
                                    get: { model.preferences.deviceResolutionEnabled },
                                    set: { model.onDeviceResolutionToggle($0) }
                                )).labelsHidden().toggleStyle(.switch)
                            }
                            if model.preferences.remoteDevices.isEmpty {
                                Text("未识别到设备，远程连接一次后自动显示。")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .font(.system(size: DesignTokens.fontCaption))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 54)
                                    .padding(.trailing, 14)
                                    .padding(.bottom, 12)
                            }
                            ForEach(model.preferences.remoteDevices) { device in
                                Divider().padding(.leading, 72)
                                SettingsView.wideControlRow(device.name, symbol: "iphone", narrow: narrow, controlWidth: nil) {
                                    HStack(spacing: 8) {
                                        GlassDropdown(
                                            label: "\(device.name)的分辨率",
                                            items: [GlassDropdownItem(id: "", title: "使用默认")]
                                                + model.preferences.customPresets.map { GlassDropdownItem(id: $0.id, title: $0.title) },
                                            selection: device.presetID,
                                            placeholder: "选择分辨率",
                                            minWidth: narrow ? 0 : DesignTokens.dropdownMinWidth,
                                            flexibleWidth: narrow
                                        ) { model.onDeviceResolutionPreset(device.id, $0.isEmpty ? nil : $0) }
                                            .disabled(!model.preferences.deviceResolutionEnabled)
                                        Button { model.onDeleteRemoteDevice(device.id) } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28, height: 28)
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除设备")
                                        .accessibilityLabel("删除\(device.name)")
                                    }
                                }
                                .padding(.leading, 18)
                            }

                            Divider().padding(.leading, 54)
                            SettingsView.settingRow("默认分辨率", symbol: "display") {
                                Toggle("默认分辨率", isOn: Binding(
                                    get: { model.preferences.defaultResolutionEnabled },
                                    set: { model.onDefaultResolutionToggle($0) }
                                )).labelsHidden().toggleStyle(.switch)
                            }
                            if model.preferences.defaultResolutionEnabled {
                                HStack {
                                    Spacer(minLength: 0)
                                    GlassDropdown(
                                        label: "默认分辨率规格",
                                        items: model.preferences.customPresets.map { GlassDropdownItem(id: $0.id, title: $0.title) },
                                        selection: model.preferences.hasAutomaticDefault ? model.preferences.autoResolutionPresetID : nil,
                                        placeholder: "请选择规格",
                                        minWidth: DesignTokens.dropdownMinWidth
                                    ) { model.onAutoResolutionPreset($0) }
                                }
                                .padding(.leading, narrow ? 14 : 54)
                                .padding(.trailing, 14)
                                .padding(.bottom, 12)
                                .zIndex(1)
                            }
                        }
                        .padding(.leading, 18)
                    }

                    Divider().padding(.leading, 54)

                    SettingsView.settingRow("断开时还原", symbol: "arrow.counterclockwise") {
                        Toggle("断开时还原", isOn: Binding(
                            get: { model.preferences.autoRestoreOnDisconnect },
                            set: { model.onAutoRestoreToggle($0) }
                        )).labelsHidden().toggleStyle(.switch)
                    }
                }
            }
            .zIndex(1)

            section("窗口") {
                SettingsView.settingRow("远程时窗口自动铺满", symbol: "arrow.up.left.and.arrow.down.right.square") {
                    Toggle("远程时窗口自动铺满", isOn: Binding(
                        get: { model.preferences.autoFillWindowsOnRemote },
                        set: { model.onAutoFillWindowsToggle($0) }
                    )).labelsHidden().toggleStyle(.switch)
                }
            }

            section("程序坞") {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsView.wideControlRow("连接时的程序坞", symbol: "dock.rectangle", narrow: narrow, controlWidth: nil) {
                        GlassDropdown(
                            label: "连接时的程序坞",
                            items: ConnectionDockMode.allCases.map { GlassDropdownItem(id: $0, title: $0.title) },
                            selection: model.preferences.connectionDockMode,
                            minWidth: DesignTokens.dropdownMinWidth
                        ) { model.onConnectionDockMode($0) }
                    }
                    if model.preferences.connectionDockMode != .keep {
                        Text("断开连接后恢复你原来的设置")
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.secondary)
                            .padding(.leading, narrow ? 14 : 54)
                            .padding(.trailing, 14)
                            .padding(.top, -4)
                            .padding(.bottom, 10)
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: DesignTokens.fontBody, weight: .semibold)).foregroundStyle(.secondary)
            SettingsView.settingCard(content)
        }
    }
}
