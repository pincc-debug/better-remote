import Foundation

public enum ScreenPreset: String, Codable, CaseIterable, Sendable {
    case phone, widescreen, tablet, wideTablet, portrait
    /// Built-in names carry their purpose, never a ratio: （保留操作栏）= 画面不被远程软件的操作栏遮挡，（全屏）= 铺满整个手机屏幕.
    public var title: String {
        switch self {
        case .phone: "手机横屏（全屏）"
        case .widescreen: "标准宽屏"
        case .tablet: "平板横屏"
        case .wideTablet: "宽屏平板"
        case .portrait: "手机竖屏（全屏）"
        }
    }
    public var name: String {
        switch self {
        case .phone: "手机横屏"
        case .widescreen: "标准宽屏"
        case .tablet: "平板横屏"
        case .wideTablet: "宽屏平板"
        case .portrait: "手机竖屏"
        }
    }
    public var ratio: String {
        switch self {
        case .phone: "20:9"
        case .widescreen: "16:9"
        case .tablet: "4:3"
        case .wideTablet: "16:10"
        case .portrait: "9:20"
        }
    }
    public var subtitle: String {
        switch self {
        case .phone: "主流全面屏手机横向持握"
        case .widescreen: "电脑显示器常见宽屏比例"
        case .tablet: "iPad 及常规平板电脑"
        case .wideTablet: "宽屏平板与轻薄笔记本"
        case .portrait: "手机竖屏纵向直向持握"
        }
    }
    public func dimensions(_ size: DisplaySize) -> Dimensions {
        let values: [Dimensions]
        switch self {
        case .phone: values = [.init(1200, 540), .init(1400, 630), .init(1600, 720)]
        case .widescreen: values = [.init(1024, 576), .init(1280, 720), .init(1600, 900)]
        case .tablet: values = [.init(896, 672), .init(1024, 768), .init(1280, 960)]
        case .wideTablet: values = [.init(1120, 700), .init(1280, 800), .init(1600, 1000)]
        case .portrait: values = [.init(540, 1200), .init(630, 1400), .init(720, 1600)]
        }
        return values[size.index]
    }
}

public enum DisplaySize: String, Codable, CaseIterable, Sendable {
    case larger, standard, moreSpace
    public var title: String {
        switch self { case .larger: "更大文字"; case .standard: "默认"; case .moreSpace: "更多空间" }
    }
    public var scaleLabel: String {
        switch self { case .larger: "85%"; case .standard: "100%"; case .moreSpace: "120%" }
    }
    public var hint: String {
        switch self {
        case .larger: "放大界面元素，便于小屏触控与阅读"
        case .standard: "macOS 标准显示排版比例"
        case .moreSpace: "容纳更多桌面应用与窗口内容"
        }
    }
    public var index: Int {
        switch self { case .larger: 0; case .standard: 1; case .moreSpace: 2 }
    }
}

public struct Dimensions: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    public var label: String { "\(width)×\(height)" }
    public var cli: String { "\(width)x\(height)" }
}

public enum ToolbarSide: String, Codable, CaseIterable, Sendable {
    case left, right, top, bottom
    public var isHorizontal: Bool { self == .top || self == .bottom }
    public var title: String {
        switch self {
        case .left: "左侧"
        case .right: "右侧"
        case .top: "上方"
        case .bottom: "下方"
        }
    }
    public var collapseSymbol: String {
        switch self {
        case .left: "chevron.left.2"
        case .right: "chevron.right.2"
        case .top: "chevron.up.2"
        case .bottom: "chevron.down.2"
        }
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var theme: AppTheme = .dark
    public var preset: ScreenPreset = .phone
    public var size: DisplaySize = .standard
    public var customPresets: [CustomPreset] = CustomPreset.factorySpecs()
    public var floatingActionIcons: [String: String] = [:]
    public var applicationShortcutsEnabled: Bool = false
    public var applicationShortcuts: [ApplicationShortcuts] = []
    public var namedShortcuts: [NamedShortcut] = []
    public var operationOrder: [String] = []
    public var floatingActions: [FloatingAction] = FloatingAction.defaults
    public var toolbarSide: ToolbarSide = .right
    public var selectedCustomID: String?
    public var seededFactorySpecs: Bool = true
    /// New installs select 手机横屏（保留操作栏） in 默认配置 · 分辨率规格. Decode keeps saved on/off (missing key → off).
    public var autoResolutionEnabled: Bool = true
    public var remoteDevices: [RemoteDevice] = []
    public var deviceResolutionEnabled: Bool = true
    public var defaultResolutionEnabled: Bool = true
    /// New installs (and a fresh preferences file) target 手机横屏（保留操作栏）; saved choices are decoded as-is.
    public var autoResolutionPresetID: String? = CustomPreset.recommendedLandscapeID
    /// 连接自动化 · 连接时的程序坞. Replaces the 0.8.145-and-earlier 「连接时显示」 toggle (on → 始终显示).
    public var connectionDockMode: ConnectionDockMode = .keep
    /// 桌面工具条 · 远程连接时显示: expanded toolbar while a remote session is connected. On by default.
    public var toolbarWhenConnected: Bool = true
    /// 桌面工具条 · 未连接时显示: expanded toolbar while nobody is connected. Off by default.
    public var toolbarWhenDisconnected: Bool = false
    /// 连接自动化 · 远程时窗口自动铺满: fill newly opened / activated standard windows while connected. Off by default.
    public var autoFillWindowsOnRemote: Bool = false
    /// Restore the computer screen when the remote connection ends. On by default.
    public var autoRestoreOnDisconnect: Bool = true
    /// 多屏保持扩展. Off (default): one virtual source, every physical display mirrors it.
    /// On: each screen is its own desktop at the same target size. Missing key stays off.
    public var keepMultiDisplayExtended: Bool = false
    /// UU Remote: one-finger swipe scrolls, long press drags. Off by default.
    public var uuTouchScrollEnabled: Bool = false
    /// Optional slowdown for UU native wheel events, independent of one-finger conversion.
    public var uuScrollSpeedPercent: Int = UUScrollScaling.defaultPercent
    /// 反转滚动方向: negate both axes of UU-injected wheel events while connected. Off by default.
    public var remoteScrollReversed: Bool = false
    /// Fixed close / minimize / full-screen group on the toolbar. On by default.
    public var showWindowControls: Bool = true
    /// One-time migration: 最小化 joins the toolbar right after 铺满 for existing users.
    public var seededMinimizeAction: Bool = true
    public var seededShowDesktopAction: Bool = true
    public init() {}
    public var selectedCustom: CustomPreset? { customPresets.first { $0.id == selectedCustomID } }
    public var dimensions: Dimensions { selectedCustom?.dimensions(.standard) ?? preset.dimensions(size) }
    public var resolutionAdjustment: ResolutionAdjustment { selectedCustom?.adjustment ?? ResolutionAdjustment(preset.dimensions(size)) }
    public var hasAutomaticDefault: Bool { customPresets.contains { $0.id == autoResolutionPresetID } }
    public var needsRemoteConnectionMonitoring: Bool {
        uuTouchScrollEnabled || connectionDockMode != .keep || toolbarWhenConnected || toolbarWhenDisconnected || autoFillWindowsOnRemote || autoRestoreOnDisconnect || (autoResolutionEnabled && hasAutomaticDefault)
    }
    public mutating func setAutomaticResolutionEnabled(_ enabled: Bool) {
        autoResolutionEnabled = enabled
        if enabled && !hasAutomaticDefault {
            autoResolutionPresetID = customPresets.first?.id
        }
    }
    private enum CodingKeys: String, CodingKey { case applicationShortcutsEnabled, applicationShortcuts, theme, toolbarSide, preset, size, customPresets, selectedCustomID, floatingActions, namedShortcuts, operationOrder, floatingActionIcons, seededFactorySpecs, autoResolutionEnabled, remoteDevices, deviceResolutionEnabled, defaultResolutionEnabled, autoResolutionPresetID, connectionDockMode, toolbarWhenConnected, toolbarWhenDisconnected, autoFillWindowsOnRemote, uuTouchScrollEnabled, uuScrollSpeedPercent, remoteScrollReversed, autoRestoreOnDisconnect, keepMultiDisplayExtended, showWindowControls, seededMinimizeAction, seededShowDesktopAction }
    /// Pre-0.8.138 toolbar keys and the pre-0.8.146 Dock toggle, read once to migrate and never written again.
    private enum LegacyKeys: String, CodingKey { case autoExpandToolbarOnConnect, autoManageToolbarOnDisconnect, autoShowDockOnConnect, uuScrollSpeedEnabled }
    /// 连接时展开 on → 远程连接时显示 on; 断开时收起 off → 未连接时显示 on. Missing keys use the old defaults (on / on).
    public static func migratedToolbarVisibility(expandOnConnect: Bool?, manageOnDisconnect: Bool?) -> (whenConnected: Bool, whenDisconnected: Bool) {
        (expandOnConnect ?? true, !(manageOnDisconnect ?? true))
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = AppTheme(rawValue: try c.decodeIfPresent(String.self, forKey: .theme) ?? "") ?? .system
        floatingActionIcons = (try c.decodeIfPresent([String: String].self, forKey: .floatingActionIcons) ?? [:]).filter {
            FloatingAction(rawValue: $0.key) != nil && ShortcutIcon(rawValue: $0.value) != nil
        }
        applicationShortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .applicationShortcutsEnabled) ?? false
        applicationShortcuts = try c.decodeIfPresent([ApplicationShortcuts].self, forKey: .applicationShortcuts) ?? []
        namedShortcuts = (try c.decodeIfPresent([NamedShortcut].self, forKey: .namedShortcuts) ?? []).filter(\.isValid)
        operationOrder = (try c.decodeIfPresent([String].self, forKey: .operationOrder) ?? []).filter {
            $0 != "builtin:previousApplication" && $0 != "builtin:leftWorkspace" &&
                !FloatingAction.persistentActions.map { "builtin:\($0.rawValue)" }.contains($0)
        }
        let storedActions = try c.decodeIfPresent([String].self, forKey: .floatingActions)
        let validActions = storedActions?.compactMap(FloatingAction.init(rawValue:)) ?? FloatingAction.defaults
        var seen = Set<FloatingAction>()
        floatingActions = validActions.filter { FloatingAction.configurableActions.contains($0) && seen.insert($0).inserted }
        toolbarSide = try c.decodeIfPresent(ToolbarSide.self, forKey: .toolbarSide) ?? .right
        preset = try c.decodeIfPresent(ScreenPreset.self, forKey: .preset) ?? .phone
        size = try c.decodeIfPresent(DisplaySize.self, forKey: .size) ?? .standard
        customPresets = (try c.decodeIfPresent([CustomPreset].self, forKey: .customPresets) ?? []).filter { (try? $0.validate()) != nil }
        selectedCustomID = try c.decodeIfPresent(String.self, forKey: .selectedCustomID)
        autoResolutionEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoResolutionEnabled) ?? false
        defaultResolutionEnabled = try c.decodeIfPresent(Bool.self, forKey: .defaultResolutionEnabled) ?? true
        deviceResolutionEnabled = try c.decodeIfPresent(Bool.self, forKey: .deviceResolutionEnabled) ?? true
        remoteDevices = try c.decodeIfPresent([RemoteDevice].self, forKey: .remoteDevices) ?? []
        var deviceIDs = Set<String>()
        remoteDevices = remoteDevices.filter { $0.id.hasPrefix("uu:") && deviceIDs.insert($0.id).inserted }
        for index in remoteDevices.indices {
            if !customPresets.contains(where: { $0.id == remoteDevices[index].presetID }) { remoteDevices[index].presetID = nil }
        }
        autoResolutionPresetID = try c.decodeIfPresent(String.self, forKey: .autoResolutionPresetID)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        connectionDockMode = (try? c.decodeIfPresent(ConnectionDockMode.self, forKey: .connectionDockMode))
            ?? ConnectionDockMode.migrated(autoShowDockOnConnect: try? legacy.decodeIfPresent(Bool.self, forKey: .autoShowDockOnConnect))
        let migrated = Self.migratedToolbarVisibility(
            expandOnConnect: try? legacy.decodeIfPresent(Bool.self, forKey: .autoExpandToolbarOnConnect),
            manageOnDisconnect: try? legacy.decodeIfPresent(Bool.self, forKey: .autoManageToolbarOnDisconnect))
        toolbarWhenConnected = (try? c.decodeIfPresent(Bool.self, forKey: .toolbarWhenConnected)) ?? migrated.whenConnected
        toolbarWhenDisconnected = (try? c.decodeIfPresent(Bool.self, forKey: .toolbarWhenDisconnected)) ?? migrated.whenDisconnected
        autoFillWindowsOnRemote = (try? c.decodeIfPresent(Bool.self, forKey: .autoFillWindowsOnRemote)) ?? false
        uuTouchScrollEnabled = try c.decodeIfPresent(Bool.self, forKey: .uuTouchScrollEnabled) ?? false
        uuScrollSpeedPercent = UUScrollScaling.clampedPercent(try c.decodeIfPresent(Int.self, forKey: .uuScrollSpeedPercent) ?? UUScrollScaling.defaultPercent)
        // Earlier preview builds used a separate toggle. Preserve an explicit off choice as original speed.
        if try legacy.decodeIfPresent(Bool.self, forKey: .uuScrollSpeedEnabled) == false { uuScrollSpeedPercent = 100 }
        remoteScrollReversed = try c.decodeIfPresent(Bool.self, forKey: .remoteScrollReversed) ?? false
        autoRestoreOnDisconnect = try c.decodeIfPresent(Bool.self, forKey: .autoRestoreOnDisconnect) ?? true
        keepMultiDisplayExtended = try c.decodeIfPresent(Bool.self, forKey: .keepMultiDisplayExtended) ?? false
        showWindowControls = try c.decodeIfPresent(Bool.self, forKey: .showWindowControls) ?? true
        seededMinimizeAction = try c.decodeIfPresent(Bool.self, forKey: .seededMinimizeAction) ?? false
        if !seededMinimizeAction {
            if !floatingActions.contains(.minimizeWindow) {
                if let index = floatingActions.firstIndex(of: .fillWindow) { floatingActions.insert(.minimizeWindow, at: index + 1) }
                else if storedActions == nil { floatingActions.append(.minimizeWindow) }
            }
            let fill = "builtin:\(FloatingAction.fillWindow.rawValue)", minimize = "builtin:\(FloatingAction.minimizeWindow.rawValue)"
            if !operationOrder.contains(minimize), let index = operationOrder.firstIndex(of: fill) { operationOrder.insert(minimize, at: index + 1) }
            seededMinimizeAction = true
        }
        seededShowDesktopAction = try c.decodeIfPresent(Bool.self, forKey: .seededShowDesktopAction) ?? false
        if !seededShowDesktopAction {
            if !floatingActions.contains(.showDesktop) {
                if let index = floatingActions.firstIndex(of: .minimizeWindow) { floatingActions.insert(.showDesktop, at: index + 1) }
                else if storedActions == nil { floatingActions.append(.showDesktop) }
            }
            let minimize = "builtin:\(FloatingAction.minimizeWindow.rawValue)", desktop = "builtin:\(FloatingAction.showDesktop.rawValue)"
            if !operationOrder.contains(desktop), let index = operationOrder.firstIndex(of: minimize) { operationOrder.insert(desktop, at: index + 1) }
            seededShowDesktopAction = true
        }
        seededFactorySpecs = try c.decodeIfPresent(Bool.self, forKey: .seededFactorySpecs) ?? false
        if !seededFactorySpecs {
            let existing = Set(customPresets.map(\.id))
            customPresets = CustomPreset.factorySpecs().filter { !existing.contains($0.id) } + customPresets
            seededFactorySpecs = true
        }
        if autoResolutionPresetID != nil && !customPresets.contains(where: { $0.id == autoResolutionPresetID }) {
            autoResolutionPresetID = nil
        }
        migrateDeviceConfigurations()
        for index in remoteDevices.indices {
            if let id = remoteDevices[index].configuration?.autoResolutionPresetID,
               !customPresets.contains(where: { $0.id == id }) {
                remoteDevices[index].configuration?.autoResolutionPresetID = nil
            }
        }
    }
}

public struct CustomPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var scalePercent: Int
    public init(id: String = UUID().uuidString, name: String, width: Int, height: Int, scalePercent: Int = 100) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.scalePercent = scalePercent
    }
    private enum CodingKeys: String, CodingKey { case id, name, width, height, scalePercent }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        scalePercent = try c.decodeIfPresent(Int.self, forKey: .scalePercent) ?? 100
    }
    public var adjustment: ResolutionAdjustment {
        ResolutionAdjustment(.init(width, height)).settingScale(scalePercent) ?? ResolutionAdjustment(.init(width, height))
    }
    public func settingScale(_ percent: Int) -> Self? {
        var next = self
        next.scalePercent = percent
        return (try? next.validate()) != nil ? next : nil
    }
    /// One size label everywhere: stored pixels, plus the display size when it is not 100%.
    public var sizeLabel: String {
        "\(width) × \(height)" + (scalePercent == 100 ? "" : " · \(scalePercent)%")
    }
    public var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "规格" : trimmed
    }
    /// Sizes that fit the 悠悠远程 phone client on a standard 20:9 phone without overlapping its toolbars (2026-10-20).
    /// The virtual display only needs 512…3840 logical points per side (HiDPI ×2); no divisibility rule applies.
    public static let recommendedLandscapeID = "factory:phoneRecommended"
    public static let recommendedPortraitID = "factory:portraitRecommended"
    public static var recommendedSpecs: [CustomPreset] {
        [CustomPreset(id: recommendedLandscapeID, name: "手机横屏（保留操作栏）", width: 1294, height: 720),
         CustomPreset(id: recommendedPortraitID, name: "手机竖屏（保留操作栏）", width: 604, height: 1138)]
    }
    /// Built-in default list: the two recommended phone sizes first, then the earlier phone sizes as alternatives,
    /// then the rest. IDs of the earlier entries (factory:<ScreenPreset>) are unchanged so saved selections keep resolving.
    public static func factorySpecs() -> [CustomPreset] {
        let order: [ScreenPreset] = [.phone, .portrait, .widescreen, .tablet, .wideTablet]
        return recommendedSpecs + order.map { preset in
            let dimensions = preset.dimensions(.standard)
            return CustomPreset(id: "factory:\(preset.rawValue)", name: preset.title, width: dimensions.width, height: dimensions.height)
        }
    }
    public func dimensions(_ size: DisplaySize) -> Dimensions {
        let scale: Double
        switch size { case .larger: scale = 0.85; case .standard: scale = 1; case .moreSpace: scale = 1.2 }
        return .init(Int((Double(width) * scale * 100 / Double(max(1, scalePercent))).rounded()),
                     Int((Double(height) * scale * 100 / Double(max(1, scalePercent))).rounded()))
    }
    public static func isSupported(_ d: Dimensions) -> Bool {
        (512...3840).contains(d.width) && (512...3840).contains(d.height)
    }
    public func validate() throws {
        guard (512...3840).contains(width), (512...3840).contains(height) else {
            throw FitError.message("宽度与高度均须在 512 至 3840 逻辑像素范围内。")
        }
        guard (50...200).contains(scalePercent), Self.isSupported(dimensions(.standard)) else {
            throw FitError.message("显示大小须在 50% 至 200% 范围内，缩放后的尺寸须在支持范围内。")
        }
    }

    public static var deviceTemplates: [CustomPreset] {
        (try? DeviceTemplateCatalog.bundled().entries.map(\.preset)) ?? []
    }
}

public struct DisplayMode: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refresh: Double
    public var modeID: Int
    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double, modeID: Int = 0) {
        self.width = width; self.height = height; self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight; self.refresh = refresh; self.modeID = modeID
    }
    public func matches(_ other: Self) -> Bool {
        width == other.width && height == other.height && pixelWidth == other.pixelWidth &&
        pixelHeight == other.pixelHeight && abs(refresh - other.refresh) < 1
    }
}

public struct DisplayState: Codable, Sendable {
    public var id: UInt32
    public var uuid: String?
    public var hardwareKey: String
    public var physical: Bool
    public var main: Bool
    public var x: Int32
    public var y: Int32
    public var mirror: UInt32
    public var mode: DisplayMode
    public var skipMode: Bool = false
    public var skipOrigin: Bool = false
    public init(id: UInt32, uuid: String?, hardwareKey: String, physical: Bool, main: Bool,
                x: Int32, y: Int32, mirror: UInt32, mode: DisplayMode) {
        self.id = id; self.uuid = uuid; self.hardwareKey = hardwareKey; self.physical = physical
        self.main = main; self.x = x; self.y = y; self.mirror = mirror; self.mode = mode
    }
}

public enum FitError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

public enum RestorePlan {
    public enum Outcome: Equatable {
        /// Put the saved physical layout back.
        case restore([DisplayState])
        /// Physical displays are online but none from the snapshot: release the virtual display, let macOS arrange.
        case release
        /// No physical display online (headless Mac mini, monitor asleep): keep the virtual display and the snapshot.
        case deferred

        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.release, .release), (.deferred, .deferred): return true
            case (.restore(let a), .restore(let b)): return a.map(\.id) == b.map(\.id)
            default: return false
            }
        }
    }

    public static func outcome(saved: [DisplayState], live: [DisplayState]) throws -> Outcome {
        // macOS's headless placeholder is not a monitor: lid closed + monitor off stays deferred,
        // so the virtual display (the only usable remote desktop) is kept.
        let live = HeadlessPlaceholder.ignoringPlaceholders(live)
        let saved = HeadlessPlaceholder.mirrorable(saved)
        guard live.contains(where: \.physical) else { return .deferred }
        guard !saved.isEmpty else { return .release }
        let mapped = try mapping(saved: saved, live: live)
        return mapped.isEmpty ? .release : .restore(try targets(saved: saved, live: live))
    }

    private static func mapping(saved: [DisplayState], live: [DisplayState]) throws -> [UInt32: DisplayState] {
        var mapped: [UInt32: DisplayState] = [:]
        for old in saved {
            let exact = old.uuid.flatMap { key in live.first { $0.uuid == key } }
            let matching = live.filter { $0.physical && $0.hardwareKey == old.hardwareKey }
            if exact == nil && matching.count > 1 { throw FitError.message("检测到多个相同硬件特征的显示器，无法确定还原目标。已保留恢复快照。") }
            if let current = exact ?? (matching.count == 1 ? matching[0] : nil) { mapped[old.id] = current }
        }
        return mapped
    }

    /// UUID first, unique hardware identity second. Never guess between identical displays.
    public static func targets(saved: [DisplayState], live: [DisplayState]) throws -> [DisplayState] {
        let mapped = try mapping(saved: saved, live: live)
        guard !mapped.isEmpty else { throw FitError.message("原主显示器未检测到物理连接，已保留恢复快照以备重连。") }
        let originalMain = saved.first(where: \.main)
        let replacementMain = originalMain.flatMap { mapped[$0.id] } ?? mapped.values.sorted { $0.id < $1.id }.first!
        let origin = saved.first { mapped[$0.id]?.id == replacementMain.id }!
        return saved.compactMap { old in
            guard let current = mapped[old.id] else { return nil }
            var target = old
            target.id = current.id; target.uuid = current.uuid
            target.mirror = mapped[old.mirror]?.id ?? 0
            target.main = current.id == replacementMain.id
            target.x -= origin.x; target.y -= origin.y
            return target
        }
    }
}

public enum RestoreDrift {
    /// Targets (each display matched by id) whose live mode (pixel + point size + refresh),
    /// position, main flag or mirroring no longer match what was restored.
    /// macOS may re-pick a default (often HiDPI) mode for an external monitor a moment after the
    /// virtual display disappears; those targets must be re-applied.
    public static func drifted(targets: [DisplayState], live: [DisplayState]) -> [DisplayState] {
        targets.filter { target in
            guard let actual = live.first(where: { $0.id == target.id }) else { return false }
            if !target.skipMode && !actual.mode.matches(target.mode) { return true }
            if !target.skipOrigin && (actual.x != target.x || actual.y != target.y || actual.main != target.main) { return true }
            return actual.mirror != target.mirror
        }
    }
}
