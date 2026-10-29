import AppKit
import SwiftUI
import RemoteFitCore

struct DeviceListSettings: View {
    @ObservedObject var model: ControlPanelModel
    @State private var selection: String?
    @State private var deletingDeviceID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let defaultID = "default"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let selection {
                HStack {
                    Button { navigate(nil) } label: {
                        Label("连接自动化", systemImage: "chevron.left")
                    }.buttonStyle(.plain)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(selection == defaultID ? "默认配置" : model.preferences.remoteDevices.first { $0.id == selection }?.displayName ?? "设备")
                        .font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                    if selection == defaultID {
                        Text("没有对应设备配置时使用")
                            .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    DeviceConfigurationSettings(model: model, deviceID: selection == defaultID ? nil : selection)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("连接自动化").font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                    Text("当设备连接到电脑时，自动应用预设的操作和布局。")
                        .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        deviceCard("默认配置", id: nil)
                        ForEach(model.preferences.remoteDevices) { device in
                            deviceCard(device.displayName, id: device.id)
                                .contextMenu {
                                    Button("删除设备", role: .destructive) { deletingDeviceID = device.id }
                                }
                        }
                    }
                    .padding(.bottom, 8)
                }
                Text("新识别到的设备会自动显示在这里，点击即可配置。")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollIndicators(.hidden)
        .alert("删除设备？", isPresented: Binding(get: { deletingDeviceID != nil }, set: { if !$0 { deletingDeviceID = nil } })) {
            Button("取消", role: .cancel) { deletingDeviceID = nil }
            Button("删除", role: .destructive) {
                if let id = deletingDeviceID { model.onDeleteRemoteDevice(id) }
                deletingDeviceID = nil
            }
        }
        .onChange(of: model.preferences.remoteDevices.map(\.id)) { _, ids in
            if let selection, selection != defaultID, !ids.contains(selection) { navigate(nil) }
        }
    }

    private func navigate(_ id: String?) {
        if let id, id != defaultID { model.onDeviceViewed(id) }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { selection = id }
    }

    private func deviceCard(_ name: String, id: String?) -> some View {
        let configuration = model.preferences.configuration(for: id)
        let preset = model.preferences.customPresets.first { $0.id == configuration.selectedResolutionID }
        // 「不切换分辨率」时用本机当前实际分辨率做预览，不再落回手机规格占位。
        let dimensions = preset?.dimensions(.standard) ?? DeviceScreenPreview.currentScreenDimensions
        let enabled = model.preferences.appliesConfiguration(for: id)
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                if let id, let software = RemoteSoftware.savedDeviceSoftware(for: id) {
                    RemoteSoftwareBadge(software: software)
                        .layoutPriority(1)
                }
                Text(name).font(.system(size: DesignTokens.fontBody, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle).help(name)
                if let id, model.preferences.remoteDevices.first(where: { $0.id == id })?.isNew == true {
                    Text("新").font(.system(size: DesignTokens.fontCaption, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }
                Spacer(minLength: 0)
                if let id {
                    Toggle("连接时应用", isOn: Binding(
                        get: { model.preferences.appliesConfiguration(for: id) },
                        set: { model.onDeviceConfigurationEnabled(id, $0) }
                    )).labelsHidden().toggleStyle(StableBlueSwitchStyle(tooltip: "关闭后，此设备连接时不应用设备配置或默认配置。")).controlSize(.mini)
                        .accessibilityLabel("\(name)：连接时应用")
                        .help("关闭后，此设备连接时不应用设备配置或默认配置。")
                }
                Menu {
                    Button("配置设备") { navigate(id ?? defaultID) }
                    if let id {
                        Divider()
                        Button("删除设备", role: .destructive) { deletingDeviceID = id }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: DesignTokens.fontBody, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("\(name)的更多操作")
            }.frame(height: 28)
            Button { navigate(id ?? defaultID) } label: {
                DeviceScreenPreview(dimensions: dimensions, identity: id ?? defaultID)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("配置\(name)")
                .opacity(enabled ? 1 : 0.45)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .cardSurface()
    }
}

/// Software mark on the device card’s top bar, left of the name. 16pt in the 28pt bar.
private struct RemoteSoftwareBadge: View {
    var software: RemoteSoftware
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = RemoteSoftwareIcon.image(for: software) {
            Image(nsImage: image)
                .interpolation(.high)
                .frame(width: RemoteSoftwareIcon.pointSize, height: RemoteSoftwareIcon.pointSize)
                .overlay {
                    RoundedRectangle(cornerRadius: RemoteSoftwareIcon.cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0 : 0.12), lineWidth: RemoteSoftwareIcon.borderWidth)
                }
                .accessibilityLabel(software.title)
                .help(software.title)
        }
    }
}

/// All previews occupy the same area. Only the screen inside it changes aspect ratio.
private struct DeviceScreenPreview: View {
    var dimensions: Dimensions
    var identity: String

    /// Main display point size (what Better Remote treats as the live desktop resolution).
    static var currentScreenDimensions: Dimensions {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.frame
            return Dimensions(max(1, Int(frame.width.rounded())), max(1, Int(frame.height.rounded())))
        }
        return Dimensions(1440, 900)
    }

    private var size: CGSize {
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)
        let scale = min(164 / max(width, 1), 152 / max(height, 1))
        return CGSize(width: width * scale, height: height * scale)
    }
    private var colors: [Color] {
        // Stable per device, including after rename/relaunch; no user setting needed.
        let index = identity.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 4 }
        switch index {
        case 0: return [Color(red: 0.65, green: 0.90, blue: 1), Color(red: 0.15, green: 0.51, blue: 0.98), Color(red: 0.14, green: 0.16, blue: 0.76)]
        case 1: return [Color(red: 1, green: 0.80, blue: 0.88), Color(red: 0.82, green: 0.32, blue: 0.85), Color(red: 0.35, green: 0.11, blue: 0.72)]
        case 2: return [Color(red: 0.76, green: 0.81, blue: 1), Color(red: 0.43, green: 0.42, blue: 0.93), Color(red: 0.22, green: 0.15, blue: 0.65)]
        default: return [Color(red: 0.68, green: 0.94, blue: 0.94), Color(red: 0.18, green: 0.65, blue: 0.78), Color(red: 0.10, green: 0.27, blue: 0.61)]
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                let w = geometry.size.width, h = geometry.size.height
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.72))
                    path.addCurve(to: CGPoint(x: w, y: h * 0.16), control1: CGPoint(x: w * 0.45, y: h * 0.66), control2: CGPoint(x: w * 0.67, y: h * 0.25))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }.fill(LinearGradient(colors: [colors[0].opacity(0.9), colors[1], colors[2]], startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.94))
                    path.addCurve(to: CGPoint(x: w, y: h * 0.43), control1: CGPoint(x: w * 0.5, y: h * 0.72), control2: CGPoint(x: w * 0.8, y: h * 0.7))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }.fill(LinearGradient(colors: [colors[1], colors[2]], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(0.85), lineWidth: 3) }
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.65), lineWidth: 0.7) }
        .frame(width: size.width, height: size.height)
        .frame(width: 164, height: 152)
    }

}

struct DeviceConfigurationSettings: View {
    @ObservedObject var model: ControlPanelModel
    var deviceID: String?
    @Environment(\.settingsNarrow) private var narrow
    private var configuration: DeviceConfiguration { model.preferences.configuration(for: deviceID) }
    private var enabled: Bool { model.preferences.appliesConfiguration(for: deviceID) }
    @State private var nameDraft = ""
    @FocusState private var editingName: Bool
    private var device: RemoteDevice? { model.preferences.remoteDevices.first { $0.id == deviceID } }
    private func saveName() {
        guard let deviceID else { return }
        model.onDeviceName(deviceID, nameDraft)
        nameDraft = device?.displayName ?? ""
    }

    private func binding<Value>(_ key: WritableKeyPath<DeviceConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: key] }, set: { value in
            var next = configuration
            next[keyPath: key] = value
            model.onDeviceConfiguration(deviceID, next)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let deviceID {
                SettingsView.settingCard {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsView.settingRow("连接时应用", symbol: "power") {
                            Toggle("连接时应用", isOn: Binding(
                                get: { enabled },
                                set: { model.onDeviceConfigurationEnabled(deviceID, $0) }
                            )).labelsHidden().toggleStyle(StableBlueSwitchStyle())
                        }
                        Text("关闭后，此设备连接时不应用设备配置或默认配置。")
                            .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, narrow ? 14 : 54)
                            .padding(.trailing, 14).padding(.bottom, 12)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                if let device {
                    section("设备") {
                        VStack(spacing: 0) {
                            SettingsView.wideControlRow("设备名称", symbol: "tag", narrow: narrow, controlWidth: 300) {
                                TextField(device.name, text: $nameDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: DesignTokens.fontBody))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: 8))
                                    .focused($editingName)
                                    .onSubmit { saveName(); editingName = false }
                                    .accessibilityLabel("设备名称")
                            }
                            Divider().padding(.leading, 54)
                            SettingsView.wideControlRow(device.software == .rustDesk ? "RustDesk ID" : "设备型号", symbol: "iphone", narrow: narrow, controlWidth: nil) {
                                Text(device.name).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
                section("分辨率") {
                    VStack(spacing: 0) {
                        SettingsView.wideControlRow("分辨率规格", symbol: "aspectratio", narrow: narrow, controlWidth: nil) {
                            GlassDropdown(label: "分辨率规格", items: [GlassDropdownItem(id: "", title: "不切换分辨率")]
                                + model.preferences.customPresets.map { GlassDropdownItem(id: $0.id, title: $0.title) },
                                selection: configuration.selectedResolutionID ?? "", placeholder: "不切换分辨率",
                                minWidth: narrow ? 0 : DesignTokens.dropdownMinWidth, flexibleWidth: narrow) { id in
                                    var next = configuration
                                    next.selectResolution(id.isEmpty ? nil : id)
                                    model.onDeviceConfiguration(deviceID, next)
                                }
                        }
                        if configuration.selectedResolutionID != nil {
                            Divider().padding(.leading, 54)
                            toggle("断开后恢复原分辨率", symbol: FloatingAction.restoreDisplay.symbol, key: \.autoRestoreOnDisconnect)
                        }
                    }
                }
                section("触控") {
                    VStack(spacing: 0) {
                        toggle("单指滚动", symbol: "hand.draw", key: \.uuTouchScrollEnabled)
                        Divider().padding(.leading, 54)
                        toggle("反转滚动方向", symbol: "arrow.up.arrow.down", key: \.remoteScrollReversed)
                    }
                }
                UUScrollSpeedSettings(percent: binding(\.uuScrollSpeedPercent))
                section("窗口") {
                    toggle("远程时窗口自动铺满", symbol: "arrow.up.left.and.arrow.down.right.square", key: \.autoFillWindowsOnRemote)
                }
                section("桌面工具条") {
                    VStack(spacing: 0) {
                        toggle("连接时显示", symbol: "sidebar.right", key: \.toolbarWhenConnected)
                        Divider().padding(.leading, 54)
                        SettingsView.wideControlRow("停靠位置", symbol: "arrow.up.and.down.and.arrow.left.and.right", narrow: narrow, controlWidth: 240) {
                            Picker("停靠位置", selection: binding(\.toolbarSide)) {
                                ForEach(ToolbarSide.allCases, id: \.self) { side in
                                    Text(side.title).tag(side)
                                }
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                }
                section("程序坞") {
                    SettingsView.wideControlRow("连接时的程序坞", symbol: "dock.rectangle", narrow: narrow, controlWidth: nil) {
                        GlassDropdown(label: "连接时的程序坞", items: ConnectionDockMode.allCases.map {
                            GlassDropdownItem(id: $0, title: $0.title)
                        }, selection: configuration.connectionDockMode, minWidth: DesignTokens.dropdownMinWidth) {
                            binding(\.connectionDockMode).wrappedValue = $0
                        }
                    }
                }
            }.disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
        }.controlSize(.small)
            .onAppear { nameDraft = device?.displayName ?? "" }
            .onChange(of: editingName) { _, focused in if !focused { saveName() } }
            .onChange(of: deviceID) { _, _ in nameDraft = device?.displayName ?? "" }
            .onDisappear { if nameDraft != device?.displayName { saveName() } }
    }

    private func toggle(_ title: String, symbol: String, key: WritableKeyPath<DeviceConfiguration, Bool>) -> some View {
        SettingsView.settingRow(title, symbol: symbol) {
            Toggle(title, isOn: binding(key)).labelsHidden().toggleStyle(StableBlueSwitchStyle())
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: DesignTokens.fontBody, weight: .semibold)).foregroundStyle(.secondary)
            SettingsView.settingCard(content)
        }
    }
}

struct AutomaticResolutionSettings: View {
    @ObservedObject var model: ControlPanelModel
    var body: some View { DeviceConfigurationSettings(model: model, deviceID: nil) }
}

/// Explicit appearance keeps "on" blue even when the settings window is not key.
struct StableBlueSwitchStyle: ToggleStyle {
    var tooltip = ""
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) { configuration.isOn.toggle() }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? DesignTokens.Colors.accent : Color.secondary.opacity(0.35))
                Circle().fill(Color.white).frame(width: 15, height: 15).padding(2)
            }
            .frame(width: 32, height: 19)
            .opacity(enabled ? 1 : 0.45)
            .frame(width: 38, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch).help(tooltip)
        }
    }
}
