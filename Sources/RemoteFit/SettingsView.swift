import SwiftUI
import RemoteFitCore
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsPage {
    case general, connection, resolution, floating, touch, about
}

/// Offscreen marketing/review renders only: a fixed version label and no permission banner
/// (the test runner is never an accessibility-trusted app). Never set in the app.
struct SettingsReviewOverrides {
    var version: String
    var permissionsGranted = true
}
private struct SettingsReviewKey: EnvironmentKey { static let defaultValue: SettingsReviewOverrides? = nil }
private struct SettingsNarrowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// 设置 is narrower than SettingsWindowLayout.narrowThreshold (e.g. a phone-portrait screen):
    /// icon-only sidebar, wide controls on their own row.
    var settingsNarrow: Bool {
        get { self[SettingsNarrowKey.self] }
        set { self[SettingsNarrowKey.self] = newValue }
    }
    var settingsReview: SettingsReviewOverrides? {
        get { self[SettingsReviewKey.self] }
        set { self[SettingsReviewKey.self] = newValue }
    }
}

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsReview) private var review
    @ObservedObject private var permissions = ShortcutPermissions.shared
    @ObservedObject var model: ControlPanelModel
    @State private var draft: SpecDraft?
    @State private var page: SettingsPage
    @State private var editingShortcut: NamedShortcut?
    private struct BuiltinIconDraft: Identifiable {
        let action: FloatingAction
        var id: String { action.rawValue }
    }
    @State private var editingBuiltinIcon: BuiltinIconDraft?
    @State private var builtinIconSaveError = false
    @State private var showingPresetSheet = false
    @State private var showingDeviceTemplates = false
    @State private var pendingDeletion: DeletionTarget?
    @State private var draggedOperationID: String?
    @State private var operationCardSizes: [String: CGSize] = [:]
    @State private var narrow = false
    @StateObject private var feedback = FeedbackModel()
    private var pagePadding: CGFloat { narrow ? 16 : 24 }

    private enum DeletionTarget {
        case preset(id: String, name: String)

        var name: String {
            switch self {
            case .preset(_, let name): return name
            }
        }
    }

    init(model: ControlPanelModel, startNew: Bool = false, page: SettingsPage = .general) {
        self.model = model
        _page = State(initialValue: startNew ? .resolution : page)
        _draft = State(initialValue: startNew ? SpecDraft.adding(dimensions: model.preferences.dimensions) : nil)
    }

    /// Only report a preset as in use when the screen really sits on it: the saved
    /// target must match what the engine applied, not just bookkeeping order.
    private static func activeSelection(in model: ControlPanelModel) -> String? {
        guard let applied = model.applied, applied == model.preferences.dimensions else { return nil }
        if let id = model.preferences.selectedCustomID,
           model.preferences.customPresets.contains(where: { $0.id == id }) {
            return id
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            DesignTokens.Colors.separator.frame(width: 1)
            contentArea
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: SettingsWindowLayout.minimumSize.width, idealWidth: SettingsWindowLayout.preferredSize.width,
               minHeight: SettingsWindowLayout.minimumSize.height, idealHeight: SettingsWindowLayout.preferredSize.height)
        .onGeometryChange(for: Bool.self) { SettingsWindowLayout.isNarrow(contentWidth: $0.size.width) } action: { narrow = $0 }
        .environment(\.settingsNarrow, narrow)
        .scrollIndicators(.hidden)
        .disabled(model.terminating || model.applying)
        .sheet(item: $draft, content: specEditor)
        .alert("删除「\(pendingDeletion?.name ?? "")」？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { target in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                switch target {
                case .preset(let id, _): model.onDeleteCustom(id)
                }
                pendingDeletion = nil
            }
        }
        .onAppear { permissions.startMonitoring() }
        .onDisappear { permissions.stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.8.110"
    }

    @ViewBuilder
    private var sidebarAppIcon: some View {
        let side: CGFloat = narrow ? 32 : 48
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                    .fill(DesignTokens.Colors.accent.gradient)
                    .frame(width: side, height: side)
                Image(systemName: "display.2")
                    .font(.system(size: side / 2, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 6) {
            sidebarAppIcon
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, narrow ? 0 : 10)
                .padding(.bottom, 12)
                .accessibilityLabel("Better Remote")

            sidebarRow("常规", symbol: "gearshape", page: .general)
            sidebarRow("分辨率", symbol: "display.2", page: .resolution)
            sidebarRow("快捷操作", symbol: "sidebar.right", page: .floating)
            sidebarRow("连接自动化", symbol: "gearshape.2", page: .connection)
            sidebarRow(FeedbackCopy.page, symbol: "info.circle", page: .about)
            Spacer()

            if !(review?.permissionsGranted ?? permissions.granted) {
                Button { permissions.prepare {} } label: {
                    if narrow {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: DesignTokens.fontEmphasis))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
                            .contentShape(Rectangle())
                    } else {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: DesignTokens.fontBody))
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("需要授权")
                                .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("辅助功能未开启")
                                .font(.system(size: DesignTokens.fontCaption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: DesignTokens.fontCaption, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
                    .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .help("打开系统设置开启辅助功能权限")
                .accessibilityLabel("需要授权：辅助功能未开启，点按前往授权")
                .padding(.bottom, 4)
            }

        }
        .padding(.top, 46)
        .padding(.horizontal, narrow ? 6 : 8)
        .frame(width: narrow ? SettingsWindowLayout.compactSidebarWidth : SettingsWindowLayout.regularSidebarWidth)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Colors.pageBackground.opacity(0.5))
    }

    /// Coloured at 15pt (B art for 常规 / 分辨率 / 连接自动化, palette or whole systemBlue otherwise);
    /// selection is the row background and never turns the icon white.
    private func sidebarGlyph(_ symbol: String, selected: Bool) -> some View {
        IconArt.coloredImage(symbol, pointSize: DesignTokens.fontEmphasis)
    }

    private func sidebarRow(_ title: String, symbol: String, page target: SettingsPage) -> some View {
        let isSelected = page == target
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                page = target
            }
        } label: {
            HStack(spacing: 9) {
                sidebarGlyph(symbol, selected: isSelected)
                    .foregroundStyle(isSelected ? DesignTokens.Colors.accent : .secondary)
                    .frame(width: 20)
                if !narrow {
                    Text(title)
                        .font(.system(size: DesignTokens.fontBody, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : .secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: narrow ? .infinity : nil)
            .padding(.vertical, 8)
            .padding(.horizontal, narrow ? 0 : 10)
            .background(isSelected ? DesignTokens.Colors.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(narrow ? title : "")
        .accessibilityLabel(title)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            switch page {
            case .general: generalSettings
            case .connection: connectionSettings
            case .resolution: resolutionSettings
            case .floating: floatingSettings
            case .touch: touchSettings
            case .about: aboutSettings
            }
        }
        .background(DesignTokens.Colors.pageBackground)
    }

    // MARK: - Resolution Settings

    private var resolutionSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
                Self.pageHeader(narrow: narrow) {
                    Text("分辨率")
                        .font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                } actions: {
                    Button {
                        showingDeviceTemplates = true
                    } label: {
                        Label("设备模板", systemImage: "ipad.and.iphone")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                    }
                    .buttonStyle(DSSecondaryButtonStyle())
                    .controlSize(.small)

                    Button {
                        draft = SpecDraft.adding(dimensions: model.preferences.dimensions)
                    } label: {
                        Label("新增规格", systemImage: "plus")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .controlSize(.small)
                }

                ScrollView {
                  VStack(alignment: .leading, spacing: 12) {
                MultiDisplayExtendSetting(model: model, narrow: narrow)
                if !model.preferences.customPresets.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(model.preferences.customPresets) { preset in
                            presetRow(preset)
                        }
                    }
                    .padding(4)
                    .cardSurface()
                }


                if let detail = model.detail {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(DesignTokens.Colors.accent)
                        Text(detail)
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(DesignTokens.Colors.accentFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        .padding(pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingDeviceTemplates) {
            DeviceTemplatesView(model: model) {
                showingDeviceTemplates = false
            }
        }
    }

    private func presetRow(_ preset: CustomPreset) -> some View {
        HoverRevealRow(id: "spec:\(preset.id)") { hovering in presetRowContent(preset, hovering: hovering) }
    }

    private func presetRowContent(_ preset: CustomPreset, hovering: Bool) -> some View {
        let applied = Self.activeSelection(in: model) == preset.id
        return HStack(spacing: 12) {
            ScreenGlyph(dimensions: preset.dimensions(.standard), selected: applied, maximumWidth: 20, maximumHeight: 16, strokeOpacity: applied ? 0.85 : 0.55)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title).font(.system(size: DesignTokens.fontBody, weight: applied ? .medium : .regular)).lineLimit(1)
                Text(verbatim: preset.sizeLabel)
                    .font(.system(size: DesignTokens.fontCaption).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityLabel(Text(verbatim: "\(preset.width) × \(preset.height)，显示大小\(preset.scalePercent)%"))
            }
            .help(preset.title)
            Spacer(minLength: 0)
            Button { draft = SpecDraft.editing(preset) } label: {
                Image(systemName: "pencil").frame(width: 28, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("编辑\(preset.title)")
            // Slot stays laid out; only the glyph's opacity switches, so nothing shifts on hover.
            HoverRevealButton(hovering: hovering, label: "删除\(preset.title)") {
                pendingDeletion = .preset(id: preset.id, name: preset.title)
            } content: {
                Image(systemName: "trash").frame(width: 28, height: 32).contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(applied ? DesignTokens.Colors.accent.opacity(0.07) : Color.clear,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
        .accessibilityAddTraits(applied ? .isSelected : [])
    }

    private func specEditor(_ draft: SpecDraft) -> some View {
        SpecEditor(draft: draft, onSave: { preset in
            model.onSaveCustom(preset)
            self.draft = nil
        }, onCancel: { self.draft = nil })
    }

    private var connectionSettings: some View {
        DeviceListSettings(model: model)
            .padding(pagePadding)
    }

    private var touchSettings: some View { connectionSettings }

    private var aboutSettings: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 8) {
                    Text("Better Remote")
                        .font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                        .lineLimit(1)
                    Text(review?.version ?? appVersion)
                        .font(.system(size: DesignTokens.fontCaption, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.top, 1)
                        .padding(.bottom, 2)
                        .background(DesignTokens.Colors.secondaryFill, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
                        )
                        .accessibilityLabel("版本 \(review?.version ?? appVersion)")
                }
                .padding(.top, 14)

                Text(FeedbackCopy.slogan)
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                FeedbackSettings(model: feedback, showsCheckUpdate: review == nil)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DesignTokens.spacingXl)
                GitHubStarSettings(allowsNetwork: review == nil)
                    .padding(.top, 16)
            }
            .frame(maxWidth: 480)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, pagePadding)
    }


    // MARK: - Shared setting rows (same look as 常规)

    /// 15pt setting-row icon, coloured: the toolbar's style-B art for its actions (铺满, 程序坞, 布局 …), else the
    /// SF Symbol as palette label + systemBlue (or whole systemBlue).
    static func settingIcon(_ symbol: String) -> some View {
        IconArt.coloredImage(symbol, pointSize: DesignTokens.fontEmphasis)
            .frame(width: 28, height: 28)
    }

    static func settingRow<Accessory: View>(_ title: String, symbol: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 12) {
            settingIcon(symbol)
            Text(title).font(.system(size: DesignTokens.fontBody, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Title with trailing buttons; in a narrow window the buttons move to their own row.
    @ViewBuilder
    static func pageHeader<Title: View, Actions: View>(narrow: Bool, @ViewBuilder title: () -> Title, @ViewBuilder actions: () -> Actions) -> some View {
        if narrow {
            VStack(alignment: .leading, spacing: 10) {
                title()
                HStack(spacing: 8) { actions() }
            }
        } else {
            HStack {
                title()
                Spacer()
                actions()
            }
        }
    }

    /// A setting with a wide control (segmented picker, dropdown). Normally the control sits on
    /// the right at `controlWidth`; in a narrow window it moves to its own row below the title,
    /// starting at the card's leading edge (native segmented controls keep their intrinsic width).
    @ViewBuilder
    static func wideControlRow<Control: View>(_ title: String, symbol: String, narrow: Bool, controlWidth: CGFloat?,
                                              verticalPadding: CGFloat = 10, @ViewBuilder control: () -> Control) -> some View {
        if narrow {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    settingIcon(symbol)
                    Text(title).font(.system(size: DesignTokens.fontBody, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                control().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, verticalPadding)
        } else {
            HStack(spacing: 12) {
                settingIcon(symbol)
                Text(title).font(.system(size: DesignTokens.fontBody, weight: .medium))
                Spacer()
                control().frame(width: controlWidth)
            }
            .padding(.horizontal, 14).padding(.vertical, verticalPadding)
        }
    }

    static func settingCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .cardSurface()
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("常规")
                    .font(.system(size: DesignTokens.fontTitle, weight: .semibold))

                Self.wideControlRow("主题", symbol: "circle.lefthalf.filled", narrow: narrow, controlWidth: 240, verticalPadding: 12) {
                    Picker("主题", selection: Binding(
                        get: { model.preferences.theme }, set: { model.onTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .cardSurface()

                // Section 1: System Behavior
                VStack(alignment: .leading, spacing: 10) {
                    Text("系统行为")
                        .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        // Launch at login
                        HStack(spacing: 12) {
                            Self.settingIcon("power.circle")

                            Text("开机启动")
                                .font(.system(size: DesignTokens.fontBody, weight: .medium))

                            Spacer()

                            Toggle("开机启动", isOn: Binding(
                                get: { SMAppService.mainApp.status == .enabled },
                                set: { enable in
                                    do {
                                        if enable {
                                            if SMAppService.mainApp.status != .enabled {
                                                try SMAppService.mainApp.register()
                                            }
                                        } else {
                                            if SMAppService.mainApp.status == .enabled {
                                                try SMAppService.mainApp.unregister()
                                            }
                                        }
                                    } catch {
                                        // Ignored
                                    }
                                }
                            ))
                            .toggleStyle(StableBlueSwitchStyle())
                            .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    }
                    .cardSurface()
                }

                // Section 2: Screen Floating Toolbar
                VStack(alignment: .leading, spacing: 10) {
                    Text("桌面工具条")
                        .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        Self.settingRow("未连接时显示", symbol: "sidebar.right") {
                            Toggle("未连接时显示", isOn: Binding(
                                get: { model.preferences.toolbarWhenDisconnected },
                                set: { model.onToolbarWhenDisconnectedToggle($0) }
                            ))
                            .toggleStyle(StableBlueSwitchStyle())
                            .labelsHidden()
                        }

                    }
                    .cardSurface()
                }

                // Section 3: Permissions
                VStack(alignment: .leading, spacing: 10) {
                    Text("系统权限")
                        .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: permissions.granted ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: DesignTokens.fontEmphasis))
                            .foregroundStyle(permissions.granted ? Color.green : Color.orange)
                            .frame(width: 28, height: 28)

                        Text("辅助功能")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))

                        Spacer()

                        if !permissions.granted {
                            Button("前往授权") {
                                permissions.prepare {}
                            }
                            .buttonStyle(DSPrimaryButtonStyle())
                            .controlSize(.small)
                        } else {
                            Text("已授权")
                                .font(.system(size: DesignTokens.fontBody, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .cardSurface()
                }
            }
            .padding(pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Floating Settings

    private var floatingSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("快捷操作")
                .font(.system(size: DesignTokens.fontTitle, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    windowControlSection
                    Self.shortcutSection {
                        Self.pageHeader(narrow: narrow) {
                            Self.sectionTitle("全局操作")
                        } actions: {
                            Button {
                                showingPresetSheet = true
                            } label: {
                                Label("常用快捷操作", systemImage: "slider.horizontal.3")
                                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                            }
                            .buttonStyle(DSSecondaryButtonStyle())
                            .controlSize(.small)
                            Button {
                                permissions.prepare {
                                    editingShortcut = .init(name: "", key: .init(code: 0, modifiers: 0, label: ""))
                                }
                            } label: {
                                Label("添加操作", systemImage: "plus")
                                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                            }
                            .buttonStyle(DSPrimaryButtonStyle())
                            .controlSize(.small)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: narrow ? 1 : 2), spacing: 8) {
                            ForEach(model.preferences.orderedOperations) { operation in
                                operationCard(operation)
                                    .onDrop(of: [UTType.text], delegate: OperationCardDropDelegate(
                                        targetID: operation.id, draggedID: $draggedOperationID,
                                        operations: model.preferences.orderedOperations, move: model.onMoveOperations,
                                        reduceMotion: reduceMotion
                                    ))
                            }
                        }
                        .padding(1)
                    }
                    ApplicationShortcutsSettings(model: model)
                }
            }
        }
        .padding(pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingShortcut) { shortcut in
            ShortcutEditor(shortcut: shortcut, onSave: {
                guard model.onSaveShortcut($0) else { return false }
                editingShortcut = nil
                return true
            }, onCancel: { editingShortcut = nil }, onDelete: model.preferences.namedShortcuts.contains(where: { $0.id == shortcut.id }) ? {
                guard model.onDeleteShortcut(shortcut.id) else { return false }
                editingShortcut = nil
                return true
            } : nil)
        }
        .sheet(item: $editingBuiltinIcon) { draft in
            BuiltinIconSheet(title: draft.action.title,
                             selected: ShortcutIcon(rawValue: model.preferences.floatingActionIcons[draft.action.rawValue] ?? draft.action.symbol),
                             saveError: builtinIconSaveError,
                             onCancel: { editingBuiltinIcon = nil }) { icon in
                guard model.onFloatingActionIcon(draft.action, icon) else { builtinIconSaveError = true; return }
                editingBuiltinIcon = nil
            }
        }
        .sheet(isPresented: $showingPresetSheet) {
            RecommendedPresetsView(model: model, permissions: permissions) {
                showingPresetSheet = false
            }
        }
    }

    static func shortcutSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Groups are titles and spacing on the page background, not an outer box.
        VStack(alignment: .leading, spacing: 10, content: content)
    }

    private var windowControlSection: some View {
        Self.settingCard {
            Self.settingRow("布局", symbol: "rectangle.split.2x2") {
                Toggle("显示布局按钮", isOn: Binding(
                    get: { model.preferences.showWindowControls },
                    set: { model.onWindowControlsToggle($0) }
                )).labelsHidden().toggleStyle(StableBlueSwitchStyle()).controlSize(.small)
                    .help("显示布局按钮")
            }
        }
    }

    static func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: DesignTokens.fontBody, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func actionIcon(_ symbol: String) -> some View {
        IconArt.image(symbol, pointSize: DesignTokens.fontEmphasis, weight: .medium)
            .font(.system(size: DesignTokens.fontEmphasis, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 26)
            .accessibilityHidden(true)
    }

    private func operationCard(_ operation: ConfiguredOperation) -> some View {
        let title: String
        let symbol: String
        let subtitle: String
        let enabled: Binding<Bool>
        switch operation {
        case .shortcut(let shortcut):
            title = shortcut.name
            symbol = shortcut.icon.rawValue
            subtitle = shortcutKeyLabel(shortcut.key)
            enabled = Binding(
                get: { model.preferences.namedShortcuts.first(where: { $0.id == shortcut.id })?.enabled ?? shortcut.enabled },
                set: { model.onShortcutToggle(shortcut.id, $0) }
            )
        case .builtin(let action):
            title = action.title
            symbol = model.preferences.floatingActionIcons[action.rawValue] ?? action.symbol
            subtitle = ""
            enabled = Binding(
                get: { model.preferences.floatingActions.contains(action) },
                set: { model.onFloatingActionToggle(action, $0) }
            )
        }
        return HStack(spacing: 4) {
            OperationDragHandle(id: operation.id, title: title, cardSize: operationCardSizes[operation.id] ?? CGSize(width: 240, height: 42),
                                onBegin: { draggedOperationID = operation.id }, onEnd: { draggedOperationID = nil })
                .frame(width: 18, height: 32)
            operationHeading(title: title, symbol: symbol, subtitle: subtitle)
            Toggle(title, isOn: enabled).labelsHidden().toggleStyle(StableBlueSwitchStyle()).controlSize(.mini)
                .frame(width: 32, height: 32)
            if case .shortcut(let shortcut) = operation {
                Button {
                    permissions.prepare { editingShortcut = shortcut }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: DesignTokens.fontBody)).frame(width: 22, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("编辑").accessibilityLabel("编辑\(title)")
            } else if case .builtin(let action) = operation {
                Button {
                    builtinIconSaveError = false
                    editingBuiltinIcon = BuiltinIconDraft(action: action)
                } label: {
                    Image(systemName: "rectangle.2.swap")
                        .font(.system(size: DesignTokens.fontBody)).frame(width: 22, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("更换图标").accessibilityLabel("更换\(title)图标")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 42)
        .cardSurface()
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { operationCardSizes[operation.id] = geometry.size }
                    .onChange(of: geometry.size) { _, size in operationCardSizes[operation.id] = size }
            }
        }
        .accessibilityAction(named: "前移") { moveOperation(operation.id, direction: -1) }
        .accessibilityAction(named: "后移") { moveOperation(operation.id, direction: 1) }
    }

    private func operationHeading(title: String, symbol: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            actionIcon(symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: DesignTokens.fontBody, weight: .medium)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: DesignTokens.fontCaption).monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
    }

    private func shortcutKeyLabel(_ key: ShortcutKey) -> String {
        key.displayLabel
    }

    private func moveOperation(_ id: String, direction: Int) {
        let operations = model.preferences.orderedOperations
        guard let index = operations.firstIndex(where: { $0.id == id }),
              operations.indices.contains(index + direction) else { return }
        model.onMoveOperations(IndexSet(integer: index), direction > 0 ? index + 2 : index - 1)
    }

}

private struct OperationCardDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    let operations: [ConfiguredOperation]
    let move: (IndexSet, Int) -> Void
    let reduceMotion: Bool

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil }
    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
              let source = operations.firstIndex(where: { $0.id == draggedID }),
              let target = operations.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            move(IndexSet(integer: source), target > source ? target + 1 : target)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

/// 更换图标 sheet for a built-in floating action.
struct BuiltinIconSheet: View {
    let title: String
    let selected: ShortcutIcon?
    let saveError: Bool
    let onCancel: () -> Void
    let onPick: (ShortcutIcon) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(title)图标").font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                Spacer()
                Button("取消", action: onCancel).buttonStyle(DSSecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            IconPickerView(selected: selected, choose: onPick)
            if saveError { Text("保存失败，请重试").font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.red) }
        }
        .padding(20).dialogFrame(width: 460)
    }
}

struct SpecDraft: Identifiable {
    let id: String
    var name: String
    var width: String
    var height: String
    var isNew: Bool
    var scalePercent: Int

    static func adding(dimensions: Dimensions) -> SpecDraft {
        SpecDraft(id: UUID().uuidString, name: "", width: String(dimensions.width), height: String(dimensions.height), isNew: true, scalePercent: 100)
    }

    static func editing(_ preset: CustomPreset) -> SpecDraft {
        SpecDraft(id: preset.id, name: preset.name, width: String(preset.width), height: String(preset.height), isNew: false, scalePercent: preset.scalePercent)
    }
}

struct SpecEditor: View {
    let id: String
    let isNew: Bool
    let onSave: (CustomPreset) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var width: String
    @State private var height: String
    @State private var error: String?
    @State private var scalePercent: Int

    init(draft: SpecDraft, onSave: @escaping (CustomPreset) -> Void, onCancel: @escaping () -> Void) {
        id = draft.id
        isNew = draft.isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _width = State(initialValue: draft.width)
        _height = State(initialValue: draft.height)
        _scalePercent = State(initialValue: draft.scalePercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isNew ? "新增规格" : "编辑规格")
                    .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                Spacer()
            }

            TextField("规格名称（如：iPhone 16 Pro、外接显示器）", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("规格名称")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("宽度").font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                    TextField("宽度", text: $width)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("宽度")
                }
                Text("×")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("高度").font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                    TextField("高度", text: $height)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("高度")
                }
            }

            Stepper("显示大小：\(scalePercent)%", value: $scalePercent, in: 50...200, step: 10)

            Text("每边 512–3840")
                .font(.system(size: DesignTokens.fontCaption))
                .foregroundStyle(.secondary)

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                }
                .font(.system(size: DesignTokens.fontCaption))
                .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if !isNew {
                    Button("另存为新规格", action: { commit(saveAs: true) })
                        .buttonStyle(DSSecondaryButtonStyle())
                }
                Button("保存", action: { commit(saveAs: false) })
                    .buttonStyle(DSPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .dialogFrame(width: 420)
    }

    private func commit(saveAs: Bool) {
        guard let w = Int(width.trimmingCharacters(in: .whitespaces)),
              let h = Int(height.trimmingCharacters(in: .whitespaces)) else {
            error = "请输入整数宽度和高度。"
            return
        }
        let preset = CustomPreset(
            id: saveAs ? UUID().uuidString : id,
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)),
            width: w,
            height: h,
            scalePercent: scalePercent
        )
        do {
            try preset.validate()
            onSave(preset)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RecommendedPresetsView: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var permissions: ShortcutPermissions
    let close: () -> Void
    @State private var presets: [NamedShortcut] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("常用快捷操作")
                        .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                }
                Spacer()
                Button(action: close) { IconArt.closeGlyph() }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(presets) { preset in
                        let alreadyAdded = model.preferences.namedShortcuts.contains { $0.name == preset.name }
                        HStack(spacing: 12) {
                            IconArt.image(preset.icon.rawValue, pointSize: DesignTokens.fontEmphasis, weight: .medium)
                                .font(.system(size: DesignTokens.fontEmphasis, weight: .medium))
                                .frame(width: 32, height: 32)
                                .background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                                Text(keyDescription(preset.key))
                                    .font(.system(size: DesignTokens.fontCaption).monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if alreadyAdded {
                                Label("已添加", systemImage: "checkmark")
                                    .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DesignTokens.Colors.secondaryFill, in: Capsule())
                            } else {
                                Button("添加") {
                                    permissions.prepare {
                                        addPreset(preset)
                                    }
                                }
                                .buttonStyle(DSSecondaryButtonStyle())
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .cardSurface()
                    }
                    if presets.isEmpty {
                        Text(loadError ?? "暂无快捷操作预设")
                            .font(.system(size: DesignTokens.fontBody)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                let unadded = presets.filter { preset in
                    !model.preferences.namedShortcuts.contains { $0.name == preset.name }
                }
                if !unadded.isEmpty {
                    Button("全部添加 (\(unadded.count))") {
                        permissions.prepare {
                            for p in unadded {
                                addPreset(p)
                            }
                        }
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .controlSize(.regular)
                }
                Button("完成", action: close)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .dialogFrame(width: 440, height: 480)
        .background(DesignTokens.Colors.pageBackground)
        .onAppear {
            do {
                let override = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/RemoteFit/shortcut-presets.json")
                presets = try ShortcutPresetCatalog.load(overrideURL: override).presets
                loadError = nil
            } catch {
                presets = []
                loadError = "无法读取快捷操作预设"
            }
        }
    }

    private func addPreset(_ preset: NamedShortcut) {
        var shortcut = preset
        shortcut.id = UUID().uuidString
        _ = model.onSaveShortcut(shortcut)
    }

    private func keyDescription(_ key: ShortcutKey) -> String {
        var parts: [String] = []
        if key.modifiers & (1 << 23) != 0 { parts.append("Fn") }
        if key.modifiers & (1 << 18) != 0 { parts.append("⌃") }
        if key.modifiers & (1 << 19) != 0 { parts.append("⌥") }
        if key.modifiers & (1 << 17) != 0 { parts.append("⇧") }
        if key.modifiers & (1 << 20) != 0 { parts.append("⌘") }
        parts.append(key.label)
        return parts.joined(separator: " ")
    }
}

struct DeviceTemplatesView: View {
    @ObservedObject var model: ControlPanelModel
    let close: () -> Void
    @State private var catalog: DeviceTemplateCatalog?
    @State private var loadError: String?
    @State private var categoryID = ""
    @State private var brandID = ""
    @State private var query = ""

    private var brands: [DeviceTemplateCatalog.Brand] {
        var seen = Set<String>()
        return (catalog?.categories ?? []).filter { categoryID.isEmpty || $0.id == categoryID }
            .flatMap(\.brands).filter { seen.insert($0.id).inserted }
    }
    private var entries: [DeviceTemplateCatalog.Entry] {
        (catalog?.entries ?? []).filter {
            (categoryID.isEmpty || $0.categoryID == categoryID) &&
            (brandID.isEmpty || $0.brandID == brandID) && $0.matches(query)
        }
    }
    private func existingPreset(for entry: DeviceTemplateCatalog.Entry) -> CustomPreset? {
        model.preferences.customPresets.first {
            $0.id == entry.preset.id || ($0.width == entry.logicalWidth && $0.height == entry.logicalHeight)
        }
    }

    private static let designedWidth: CGFloat = 580
    @Environment(\.dialogLimitOverride) private var dialogLimitOverride

    private var categoryPicker: some View {
        Picker("设备类型", selection: $categoryID) {
            Text("全部").tag("")
            ForEach(catalog?.categories ?? []) { category in Text(category.name).tag(category.id) }
        }.pickerStyle(.segmented)
    }
    private var brandPicker: some View {
        Picker("品牌", selection: $brandID) {
            Text("全部品牌").tag("")
            ForEach(brands) { brand in Text(brand.name).tag(brand.id) }
        }.labelsHidden().frame(width: 130)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("设备模板").font(.system(size: DesignTokens.fontEmphasis, weight: .medium))
                Spacer()
                Button(action: close) { IconArt.closeGlyph() }
                    .buttonStyle(.plain).accessibilityLabel("关闭")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索型号", text: $query).textFieldStyle(.plain).accessibilityLabel("搜索设备型号")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }.padding(10).background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
            // On a narrowed sheet the brand menu moves under the category picker.
            if DialogLimit.current(dialogLimitOverride).width < Self.designedWidth {
                VStack(alignment: .leading, spacing: 8) { categoryPicker; brandPicker }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) { categoryPicker; brandPicker }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(entries) { entry in templateRow(entry) }
                    if entries.isEmpty {
                        Text(loadError ?? (query.isEmpty ? "暂无匹配的设备" : "未找到与“\(query)”匹配的设备"))
                            .font(.system(size: DesignTokens.fontBody)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
        }
        .padding(20).dialogFrame(width: Self.designedWidth, height: 510)
        .background(DesignTokens.Colors.pageBackground)
        .onChange(of: categoryID) { _, _ in brandID = "" }
        .onAppear {
            do {
                let override = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/RemoteFit/device-templates.json")
                catalog = try DeviceTemplateCatalog.load(overrideURL: override)
            } catch { loadError = "无法读取设备模板" }
        }
    }

    private func templateRow(_ entry: DeviceTemplateCatalog.Entry) -> some View {
        let existing = existingPreset(for: entry)
        let applied = existing.map {
            model.preferences.selectedCustomID == $0.id && model.applied == $0.dimensions(.standard)
        } ?? false
        return HStack(spacing: 12) {
            ScreenGlyph(dimensions: .init(entry.logicalWidth, entry.logicalHeight), selected: applied, strokeOpacity: 0.55)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.system(size: DesignTokens.fontBody, weight: .medium)).lineLimit(1)
                Text(verbatim: "\(entry.logicalWidth) × \(entry.logicalHeight)").font(.system(size: DesignTokens.fontCaption).monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if applied {
                Label("使用中", systemImage: "checkmark.circle.fill").font(.system(size: DesignTokens.fontBody)).foregroundStyle(DesignTokens.Colors.accent)
            } else if existing != nil {
                Label("已添加", systemImage: "checkmark").font(.system(size: DesignTokens.fontBody)).foregroundStyle(.secondary)
            } else {
                Button("添加") { model.onSaveCustom(entry.preset) }.buttonStyle(DSSecondaryButtonStyle()).controlSize(.small)
            }
        }
        .padding(12).cardSurface()
    }
}

/// Row that reports pointer hover (app-wide `PointerHover` owner) to its content.
private struct HoverRevealRow<Content: View>: View {
    let id: String
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    var body: some View { content(hovering).pointerHover(id) { hovering = $0 } }
}

/// Destructive row button that is drawn only while the row is hovered or the button has keyboard / VoiceOver focus.
/// The button itself stays in the view and accessibility tree (only its glyph fades), so VoiceOver keeps its label.
private struct HoverRevealButton<Content: View>: View {
    let hovering: Bool
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var voiceOverFocused: Bool
    var body: some View {
        let shown = hovering || focused || voiceOverFocused
        Button(role: .destructive, action: action) { content().opacity(shown ? 1 : 0) }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .focused($focused)
            .accessibilityFocused($voiceOverFocused)
            .accessibilityLabel(label)
            .allowsHitTesting(shown)
    }
}
