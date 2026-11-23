import AppKit
import SwiftUI
import RemoteFitCore

struct DeviceListSettings: View {
    @ObservedObject var model: ControlPanelModel
    var onManageResolutions: (() -> Void)? = nil
    @State private var selection: String?
    @State private var deletingDeviceID: String?
    @State private var hoveredCardID: String?
    @State private var hoveredGearID: String?
    /// Offscreen review only: open this detail page directly.
    nonisolated(unsafe) static var forcedSelection: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.settingsNarrow) private var narrow
    /// Offscreen review only: render this card ("default" or a device id) in its hover state.
    nonisolated(unsafe) static var forcedHoverCardID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let defaultID = "default"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let selection {
                HStack {
                    Button { navigate(nil) } label: {
                        Label("设备", systemImage: "chevron.left")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                    }.buttonStyle(.plain)
                    Spacer()
                }
                if selection == defaultID {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("默认配置")
                            .font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                        Text("新设备与未识别设备使用")
                            .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                    }
                }
                ScrollView {
                    DeviceConfigurationSettings(
                        model: model,
                        deviceID: selection == defaultID ? nil : selection,
                        onManageResolutions: onManageResolutions
                    )
                    if selection != defaultID {
                        VStack(spacing: 0) {
                            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
                            Button("删除设备") { deletingDeviceID = selection }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color(nsColor: .systemRed))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                                .padding(.bottom, 16)
                        }.padding(.top, 8)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text("设备").font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                    if model.isRemoteConnected {
                        statusPill("远程已连接")
                    }
                    Spacer(minLength: 0)
                }
                if let hint = model.identifyHint {
                    HStack(spacing: DesignTokens.spacingSm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: DesignTokens.fontBody))
                            .foregroundStyle(DesignTokens.Colors.accent)
                        Text(hint.message)
                            .font(.system(size: DesignTokens.fontBody))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let title = hint.actionTitle, let action = hint.action {
                            Button(title) { model.onIdentifyHintAction(action) }
                                .buttonStyle(DSSecondaryButtonStyle())
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .cardSurface()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        defaultConfigurationBanner
                            .contextMenu { Button("编辑默认配置") { navigate(defaultID) } }

                        VStack(alignment: .leading, spacing: 10) {
                            SettingsView.sectionTitle("已连接设备")
                            if model.preferences.remoteDevices.isEmpty {
                                VStack(spacing: 6) {
                                    Text("暂无已收录设备")
                                        .font(.system(size: DesignTokens.fontBody, weight: .medium))
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    Text("远程连接后，设备会自动出现在这里，可分别配置分辨率、触控和工具条。")
                                        .font(.system(size: DesignTokens.fontCaption))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .padding(.horizontal, 20)
                                .cardSurface()
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                                    ForEach(model.preferences.remoteDevices) { device in
                                        deviceCard(device.displayName, id: device.id)
                                            .contextMenu {
                                                Button("配置设备") { navigate(device.id) }
                                                Divider()
                                                Button("删除设备", role: .destructive) { deletingDeviceID = device.id }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
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
        .onAppear { if let forced = Self.forcedSelection { selection = forced } }
        .onChange(of: model.preferences.remoteDevices.map(\.id)) { _, ids in
            if let selection, selection != defaultID, !ids.contains(selection) { navigate(nil) }
        }
    }

    private func statusPill(_ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DesignTokens.Colors.secondaryFill, in: Capsule())
    }

    private var defaultConfigurationBanner: some View {
        let configuration = model.preferences.configuration(for: nil)
        let preset = model.preferences.customPresets.first { $0.id == configuration.selectedResolutionID }
        let dimensions = preset?.dimensions(.standard) ?? DeviceScreenPreview.currentScreenDimensions
        let summary = DeviceConfigurationSummary.defaultSummary(in: model.preferences)
        let activeFallback = model.isRemoteConnected && model.connectedDeviceID == nil
        let hovered = hoveredCardID == defaultID || Self.forcedHoverCardID == defaultID
        return Button { navigate(defaultID) } label: {
            HStack(spacing: 14) {
                DeviceScreenPreview(dimensions: dimensions, identity: defaultID, compact: true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("默认配置")
                            .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        if activeFallback {
                            statusPill("生效中")
                        } else if !narrow {
                            Text("新设备与未识别时使用")
                                .font(.system(size: DesignTokens.fontCaption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text(summary)
                        .font(.system(size: DesignTokens.fontCaption))
                        .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.secondary) : AnyShapeStyle(mutedText))
                        .lineLimit(narrow ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: DesignTokens.fontCaption, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredCardID = defaultID; NSCursor.pointingHand.set() }
            else if hoveredCardID == defaultID { hoveredCardID = nil; NSCursor.arrow.set() }
        }
        .accessibilityLabel("默认配置：\(summary)")
    }

    private var gearColor: Color {
        let v: Double = colorScheme == .dark ? 0x9A : 0x8A
        return Color(red: v / 255, green: v / 255, blue: v / 255)
    }

    private var mutedText: Color {
        colorScheme == .dark ? Color(red: 0xAB / 255, green: 0xAB / 255, blue: 0xAB / 255) : Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x63 / 255)
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
        let summary = DeviceConfigurationSummary.effectiveSummary(for: id, in: model.preferences)
        let key = id ?? defaultID
        let isConnected = id != nil && model.connectedDeviceID == id
        let hovered = hoveredCardID == key || Self.forcedHoverCardID == key
        let gearHovered = hoveredGearID == key || Self.forcedHoverCardID == key
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: DesignTokens.fontBody, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle).help(name)
                if isConnected {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                        .help("已连接")
                } else if let id, model.preferences.remoteDevices.first(where: { $0.id == id })?.isNew == true {
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
                Button { navigate(key) } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: DesignTokens.fontEmphasis, weight: .light))
                        .foregroundStyle(gearColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(gearHovered ? 0.12 : 0)))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .onHover { inside in
                        if inside { hoveredGearID = key } else if hoveredGearID == key { hoveredGearID = nil }
                    }
                    .help("配置\(name)")
                    .accessibilityLabel("配置\(name)")
            }.frame(height: 28)
            Button { navigate(id ?? defaultID) } label: {
                DeviceScreenPreview(dimensions: dimensions, identity: id ?? defaultID, software: id.flatMap(RemoteSoftware.savedDeviceSoftware(for:)))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("配置\(name)")
                .opacity(enabled ? 1 : 0.45)
            Button { navigate(id ?? defaultID) } label: {
                Text(summary)
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.secondary) : AnyShapeStyle(mutedText))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5) }
                .help(summary)
                .accessibilityLabel("\(name)配置摘要：\(summary)")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 244)
        .contentShape(Rectangle())
        .onTapGesture { navigate(id ?? defaultID) }
        .background(Color.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
        .cardSurface()
        .onHover { inside in
            if inside { hoveredCardID = key; NSCursor.pointingHand.set() }
            else if hoveredCardID == key { hoveredCardID = nil; NSCursor.arrow.set() }
        }
        .onContinuousHover { phase in if case .active = phase { NSCursor.pointingHand.set() } }
    }
}

/// 16pt software mark on the preview silhouette’s bottom-left corner.
private struct RemoteSoftwareBadge: View {
    var software: RemoteSoftware
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image = RemoteSoftwareIcon.image(for: software) {
            let shape = RoundedRectangle(cornerRadius: RemoteSoftwareIcon.cornerRadius, style: .continuous)
            Image(nsImage: image)
                .interpolation(.high)
                .frame(width: RemoteSoftwareIcon.pointSize, height: RemoteSoftwareIcon.pointSize)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        (colorScheme == .dark ? Color.white : Color.black).opacity(RemoteSoftwareIcon.borderOpacity),
                        lineWidth: RemoteSoftwareIcon.borderWidth
                    )
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
    /// UU or RustDesk only. Nil on the default-configuration card.
    var software: RemoteSoftware? = nil
    var compact: Bool = false

    /// Main display point size (what Better Remote treats as the live desktop resolution).
    static var currentScreenDimensions: Dimensions {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.frame
            return Dimensions(max(1, Int(frame.width.rounded())), max(1, Int(frame.height.rounded())))
        }
        return Dimensions(1440, 900)
    }

    private var box: CGSize { compact ? CGSize(width: 48, height: 34) : CGSize(width: 164, height: 152) }
    private var cornerRadius: CGFloat { compact ? 6 : 12 }
    private var bezelWidth: CGFloat { compact ? 1.5 : 3 }

    private var size: CGSize {
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)
        let scale = min(box.width / max(width, 1), box.height / max(height, 1))
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.black.opacity(0.85), lineWidth: bezelWidth) }
        .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.65), lineWidth: compact ? 0.5 : 0.7) }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomLeading) {
            if let software, !compact {
                RemoteSoftwareBadge(software: software)
                    .padding(.leading, RemoteSoftwareIcon.inset)
                    .padding(.bottom, RemoteSoftwareIcon.inset)
            }
        }
        .frame(width: box.width, height: box.height)
    }

}

struct DeviceConfigurationSettings: View {
    @ObservedObject var model: ControlPanelModel
    var deviceID: String?
    var onManageResolutions: (() -> Void)? = nil
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
            if let deviceID, let device {
                SettingsView.settingCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            SettingsView.settingIcon("iphone")
                            VStack(alignment: .leading, spacing: 3) {
                                TextField(device.name, text: $nameDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: narrow ? .infinity : 260, minHeight: 28)
                                    .dsInputField(radius: DesignTokens.radiusSm)
                                    .focused($editingName)
                                    .onSubmit { saveName(); editingName = false }
                                    .accessibilityLabel("设备名称")
                                Text(device.software == .rustDesk ? "RustDesk ID：\(device.name)" : "UU 远程 · \(device.name)")
                                    .font(.system(size: DesignTokens.fontCaption))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .padding(.leading, 2)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 8) {
                                if !narrow {
                                    Text("连接时应用")
                                        .font(.system(size: DesignTokens.fontCaption))
                                        .foregroundStyle(.secondary)
                                }
                                Toggle("连接时应用", isOn: Binding(
                                    get: { enabled },
                                    set: { model.onDeviceConfigurationEnabled(deviceID, $0) }
                                )).labelsHidden().toggleStyle(StableBlueSwitchStyle())
                                    .help("连接时应用此设备配置")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        if !enabled {
                            Text("已停用：连接时不应用设备配置或默认配置。")
                                .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, narrow ? 14 : 54)
                                .padding(.trailing, 14).padding(.bottom, 12)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                section("分辨率", trailing: {
                    if let onManageResolutions {
                        Button("管理规格", action: onManageResolutions)
                            .buttonStyle(.plain)
                            .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.accent)
                    }
                }) {
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
                            Divider().padding(.leading, narrow ? 14 : 54)
                            toggle("断开后恢复原分辨率", symbol: FloatingAction.restoreDisplay.symbol, key: \.autoRestoreOnDisconnect)
                        }
                    }
                }
                let showsSingleFinger = device?.software?.supportsSingleFingerScroll != false
                let showsReversal = device?.software?.supportsScrollReversal != false
                let showsSpeed = device?.software?.supportsScrollSpeed != false
                if showsSingleFinger || showsReversal || showsSpeed {
                    section("触控") {
                        VStack(spacing: 0) {
                            if showsSingleFinger {
                                toggle("单指滚动", symbol: "hand.draw", key: \.uuTouchScrollEnabled)
                            }
                            if showsSingleFinger && showsReversal {
                                Divider().padding(.leading, narrow ? 14 : 54)
                            }
                            if showsReversal {
                                toggle("反转滚动方向", symbol: "arrow.up.arrow.down", key: \.remoteScrollReversed)
                            }
                            if (showsSingleFinger || showsReversal) && showsSpeed {
                                Divider().padding(.leading, narrow ? 14 : 54)
                            }
                            if showsSpeed {
                                UUScrollSpeedSettings(percent: binding(\.uuScrollSpeedPercent), embedded: true)
                            }
                        }
                    }
                }
                section("桌面工具条") {
                    VStack(spacing: 0) {
                        SettingsView.wideControlRow("连接时显示", symbol: "sidebar.right", narrow: narrow, controlWidth: 240) {
                            DSSegmentedControl("连接时显示",
                                               options: ToolbarVisibility.allCases.map { .init(value: $0, title: $0.title) },
                                               selection: binding(\.toolbarWhenConnected))
                        }
                        Divider().padding(.leading, narrow ? 14 : 54)
                        SettingsView.wideControlRow("停靠位置", symbol: "arrow.up.and.down.and.arrow.left.and.right", narrow: narrow, controlWidth: 240) {
                            DSSegmentedControl("停靠位置",
                                               options: ToolbarSide.allCases.map { .init(value: $0, title: $0.title) },
                                               selection: binding(\.toolbarSide))
                        }
                    }
                }
                section("窗口与程序坞") {
                    VStack(spacing: 0) {
                        toggle("远程时窗口自动铺满", symbol: "arrow.up.left.and.arrow.down.right.square", key: \.autoFillWindowsOnRemote)
                        Divider().padding(.leading, narrow ? 14 : 54)
                        SettingsView.wideControlRow("连接时的程序坞", symbol: "dock.rectangle", narrow: narrow, controlWidth: nil) {
                            GlassDropdown(label: "连接时的程序坞", items: ConnectionDockMode.allCases.map {
                                GlassDropdownItem(id: $0, title: $0.title)
                            }, selection: configuration.connectionDockMode, minWidth: narrow ? 0 : DesignTokens.dropdownMinWidth, flexibleWidth: narrow) {
                                binding(\.connectionDockMode).wrappedValue = $0
                            }
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
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<Trailing: View, Content: View>(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: DesignTokens.fontBody, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                trailing()
            }
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
