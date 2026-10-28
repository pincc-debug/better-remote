import AppKit
import SwiftUI
import RemoteFitCore

struct LauncherApp: Identifiable {
    var id: String
    var url: URL
    var name: String
    var icon: NSImage
    var running: Bool
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var apps: [LauncherApp] = [] { didSet { layoutChanged() } }
    @Published var recent = RecentApplications() { didSet { layoutChanged() } }
    @Published var side: ToolbarSide = .right
    @Published var panelWidth: CGFloat = 560
    @Published var presentationID = 0
    @Published var error: String? { didSet { layoutChanged() } }
    @Published var launching = false
    var open: (LauncherApp) -> Void = { _ in }
    var close: () -> Void = {}
    var layoutChanged: () -> Void = {}
    var sections: [(section: ApplicationSection, apps: [LauncherApp])] {
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        return ApplicationSection.make(
            recent: recent.available(in: Set(byID.keys)),
            running: apps.filter(\.running).map(\.id),
            all: apps.map(\.id)
        ).map { ($0, $0.identifiers.compactMap { byID[$0] }) }
    }
}

struct AppLauncherView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: LauncherModel
    @State private var hoveredAppId: String?
    @State private var previewedAppID: String?
    @State private var pressedAppID: String?

    private static let tileSize: CGFloat = ReachableApplicationGrid.minimumCellWidth
    private static let spacing: CGFloat = ReachableApplicationGrid.horizontalSpacing

    var body: some View {
        VStack(spacing: DesignTokens.spacingMd) {
            if let error = model.error {
                errorBanner(error)
            }
            GeometryReader { geometry in
                let columns = max(1, Int((geometry.size.width + Self.spacing) / (Self.tileSize + Self.spacing)))
                let sections = model.sections
                if sections.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: model.side == .right ? .trailing : .leading, spacing: DesignTokens.spacingLg) {
                            ForEach(sections, id: \.section.kind) { entry in
                                VStack(alignment: model.side == .right ? .trailing : .leading, spacing: DesignTokens.spacingSm) {
                                    sectionHeader(entry.section, count: entry.apps.count, columns: columns)
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tileSize), spacing: Self.spacing), count: min(columns, max(1, entry.apps.count))),
                                              alignment: model.side == .right ? .trailing : .leading,
                                              spacing: ReachableApplicationGrid.verticalSpacing) {
                                        ForEach(Array((model.side == .right ? mirrored(entry.apps, columns: columns) : entry.apps.map(Optional.some)).enumerated()), id: \.offset) { item in
                                            if let app = item.element { appTile(app, showsRunningDot: entry.section.kind != .running) } else { Color.clear.frame(width: Self.tileSize, height: ReachableApplicationGrid.cellHeight) }
                                        }
                                    }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel(entry.section.title)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: model.side == .right ? .trailing : .leading)
                        .padding(.vertical, DesignTokens.spacingXs)
                    }
                    .scrollIndicators(.never, axes: .vertical)
                    .overflowEdgeFade()
                }
            }
        }
        .padding(DesignTokens.spacingLg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .foregroundStyle(Color.primary)
        .onExitCommand(perform: model.close)
        .onChange(of: model.presentationID) { _, _ in previewedAppID = nil; pressedAppID = nil }
    }

    /// Right-docked panels fill rows from the toolbar edge inward, so a partial last row hugs the toolbar.
    private func mirrored(_ apps: [LauncherApp], columns: Int) -> [LauncherApp?] {
        let width = min(columns, max(1, apps.count))
        var result: [LauncherApp?] = []
        stride(from: 0, to: apps.count, by: width).forEach { start in
            var row: [LauncherApp?] = Array(apps[start..<min(apps.count, start + width)])
            row += Array(repeating: nil, count: width - row.count)
            result += row.reversed()
        }
        return result
    }

    private func sectionHeader(_ section: ApplicationSection, count: Int, columns: Int) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("\(count)")
                .font(.system(size: DesignTokens.fontBody).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - App Tile

    /// The 运行中 section is all running apps, so it drops the redundant running dot.
    private func appTile(_ app: LauncherApp, showsRunningDot: Bool = true) -> some View {
        let isHovered = hoveredAppId == app.id
        let isPressed = pressedAppID == app.id
        let isPreviewed = previewedAppID == app.id
        let shape = RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                if app.running && showsRunningDot {
                    Circle()
                        .fill(Color(red: 0.40, green: 0.70, blue: 0.53))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(DesignTokens.Colors.surface, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isPressed && !reduceMotion ? 0.92 : 1)
        }
        .frame(width: Self.tileSize, height: ReachableApplicationGrid.cellHeight)
        .background(isPreviewed || isPressed ? DesignTokens.Colors.cardBgHover : (isHovered ? DesignTokens.Colors.cardBg : Color.clear), in: shape)
        .overlay {
            if isPreviewed {
                shape.strokeBorder(DesignTokens.Colors.cardBorderHighlight, lineWidth: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if isPreviewed {
                Text(app.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                    .fixedSize()
                    .offset(y: 14)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(isPreviewed ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
        .contentShape(shape)
        .accessibilityHidden(true)
        .overlay {
            LauncherPressTarget(name: app.name + (app.running ? "（正在运行）" : ""), enabled: !model.launching,
                onTap: { previewedAppID = nil; model.open(app) },
                onPreview: { previewedAppID = app.id },
                onHighlight: { pressedAppID = $0 ? app.id : nil })
        }
        .pointerHover("app:\(app.id)") { hovering in
            hoveredAppId = hovering ? app.id : (hoveredAppId == app.id ? nil : hoveredAppId)
        }
        .help(app.name + (app.running ? "（正在运行）" : ""))
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.spacingMd) {
            Image(systemName: "square.dashed")
                .font(.system(size: 32))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.top, 16)
            Text("未找到已安装的应用")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            // Red circle = error; the orange triangle is kept for warnings (permissions).
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.red.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@MainActor
final class AppLauncher: NSObject {
    private let model = LauncherModel()
    private var panel: OverlayFloatingPanel?
    private var presentationGeneration = 0
    private var anchor: CGRect?
    private var presentationScreen: NSScreen?
    private let usageURL: URL
    private let recentURL: URL
    var onAction: (FloatingAction) -> Void = { _ in }
    var onHide: () -> Void = {}
    var onShow: () -> Void = {}
    var isVisible: Bool { panel?.isVisible == true }
    var visibleFrame: CGRect? { isVisible ? panel?.frame : nil }
    private var usage: [String: Int] = [:]

    init(root: URL) {
        usageURL = root.appendingPathComponent("app-usage.json")
        recentURL = root.appendingPathComponent("app-recent.json")
        super.init()
        if let data = try? Data(contentsOf: usageURL), let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            usage = saved
        }
        if let data = try? Data(contentsOf: recentURL), let saved = try? JSONDecoder().decode([String].self, from: data) {
            model.recent = RecentApplications(saved)
        }
        model.close = { [weak self] in self?.hide() }
        model.open = { [weak self] app in self?.open(app) }
        model.layoutChanged = { [weak self] in self?.updateFrame() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication { record(app) }
    }

    func hide() {
        presentationGeneration += 1
        panel?.orderOut(nil)
        onHide()
    }

    func show(anchor: CGRect, screen: NSScreen, side: ToolbarSide = .right) {
        self.anchor = anchor
        presentationScreen = screen
        model.side = side
        presentationGeneration += 1
        model.presentationID = presentationGeneration
        model.error = nil
        refresh()

        let frame = DesktopToolbarLayout.applications(to: anchor, in: screen.visibleFrame, side: side)
        model.panelWidth = frame.width

        let overlay = panel ?? OverlayFloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.title = "Better Remote 应用"
        overlay.backgroundColor = .clear
        overlay.level = .floating
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if panel == nil {
            overlay.contentView = glassHost(AppLauncherView(model: model), cornerRadius: 22)
        }
        panel = overlay
        overlay.setFrame(frame, display: true)
        (overlay.contentView as? NativeGlassView)?.attach(to: side)
        (overlay.contentView as? NativeGlassView)?.setHairline(DesignTokens.NS.toolbarSurfaceHairline, omitting: side)
        overlay.makeKeyAndOrderFront(nil)
        (overlay.contentView as? NativeGlassView)?.reveal(from: side)
        overlay.makeFirstResponder(nil)
    }

    func update(anchor: CGRect, screen: NSScreen, side: ToolbarSide) {
        guard isVisible else { return }
        self.anchor = anchor
        presentationScreen = screen
        model.side = side
        (panel?.contentView as? NativeGlassView)?.attach(to: side)
        (panel?.contentView as? NativeGlassView)?.setHairline(DesignTokens.NS.toolbarSurfaceHairline, omitting: side)
        updateFrame()
    }

    private func updateFrame() {
        guard let panel, panel.isVisible, let anchor, let screen = presentationScreen else { return }
        let frame = DesktopToolbarLayout.applications(to: anchor, in: screen.visibleFrame, side: model.side)
        model.panelWidth = frame.width
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        record(app)
    }

    private func record(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "local.RemoteFit", !app.isTerminated,
              let id = app.bundleIdentifier ?? app.bundleURL?.standardizedFileURL.path else { return }
        record(identifier: id)
    }

    private func record(identifier: String) {
        var recent = model.recent
        recent.record(identifier)
        guard recent != model.recent else { return }
        model.recent = recent
        try? FileManager.default.createDirectory(at: recentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(recent.identifiers).write(to: recentURL, options: .atomic)
    }

    private func refresh() {
        let roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications")
        ]
        var candidates: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                candidates.append(url)
            }
        }
        candidates += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var seen = Set<String>()
        model.apps = candidates.compactMap { url in
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier != "local.RemoteFit",
                  bundle.infoDictionary?["LSBackgroundOnly"] as? Bool != true else { return nil }
            let id = bundle.bundleIdentifier ?? url.standardizedFileURL.path
            guard seen.insert(id).inserted else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return LauncherApp(id: id, url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), running: runningIDs.contains(id))
        }.sorted {
            let aRecent = model.recent.identifiers.firstIndex(of: $0.id) ?? Int.max
            let bRecent = model.recent.identifiers.firstIndex(of: $1.id) ?? Int.max
            if aRecent != bRecent { return aRecent < bRecent }
            let a = usage[$0.id, default: 0], b = usage[$1.id, default: 0]
            if a != b { return a > b }
            if $0.running != $1.running { return $0.running }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func open(_ app: LauncherApp) {
        guard !model.launching else { return }
        model.launching = true
        let generation = presentationGeneration
        panel?.orderOut(nil)
        onHide()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.model.launching = false
                if let error {
                    if generation == self.presentationGeneration {
                        self.model.error = error.localizedDescription
                        self.panel?.makeKeyAndOrderFront(nil)
                        self.onShow()
                    }
                    return
                }
                self.usage[app.id] = min(max(0, self.usage[app.id, default: 0]), Int.max - 1) + 1
                if let active = NSWorkspace.shared.frontmostApplication,
                   (active.bundleIdentifier ?? active.bundleURL?.standardizedFileURL.path) == app.id {
                    self.record(active)
                }
                try? JSONEncoder().encode(self.usage).write(to: self.usageURL, options: .atomic)
                if generation == self.presentationGeneration {
                    self.panel?.orderOut(nil)
                }
            }
        }
    }
}
