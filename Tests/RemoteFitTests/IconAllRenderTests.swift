import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Offscreen renders of every coloured-icon area, light and dark (only with BR_ICON_ALL_RENDER=<folder>).
/// Borderless windows far off screen that are never ordered front, so nothing takes focus.
@MainActor
final class IconAllRenderTests: XCTestCase {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["BR_ICON_ALL_RENDER"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func render(_ view: NSView, size: CGSize, dark: Bool, background: NSColor, colorful: Bool = false, to url: URL) throws {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = window.appearance
        defer { NSApp.appearance = nil }
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        window.appearance?.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = background.cgColor }
        if colorful {
            let gradient = CAGradientLayer()
            gradient.frame = root.bounds
            gradient.colors = [NSColor.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple].map(\.cgColor)
            gradient.startPoint = .zero; gradient.endPoint = CGPoint(x: 1, y: 1)
            root.layer?.addSublayer(gradient)
            for index in 0..<8 {
                let stripe = CATextLayer()
                stripe.string = "Better Remote 远程桌面 \(index) ███ ▓▓▓ ░░░ Better Remote"
                stripe.fontSize = 22
                stripe.foregroundColor = (index.isMultiple(of: 2) ? NSColor.white : NSColor.black).cgColor
                stripe.frame = CGRect(x: 0, y: CGFloat(index) * size.height / 8, width: size.width, height: 30)
                root.layer?.addSublayer(stripe)
            }
        }
        view.frame.origin = CGPoint(x: (size.width - view.frame.width) / 2, y: (size.height - view.frame.height) / 2)
        root.addSubview(view)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        root.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }

    private func page<V: View>(_ content: V, size: CGSize, dark: Bool, name: String, in folder: URL) throws {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
            .background(DesignTokens.Colors.pageBackground))
        host.frame = CGRect(origin: .zero, size: size)
        try render(host, size: size, dark: dark, background: .windowBackgroundColor,
                   to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    private func reviewModel() -> ControlPanelModel {
        let model = ControlPanelModel()
        model.preferences.remember(.init(id: "uu:window:Phone", name: "iPhone 13"))
        model.preferences.setAutomaticResolutionEnabled(true)
        model.preferences.autoResolutionPresetID = model.preferences.customPresets.first?.id
        model.preferences.applicationShortcutsEnabled = true
        let presets = Array(NamedShortcut.recommendedPresets.prefix(4))
        model.preferences.applicationShortcuts = [ApplicationShortcuts(bundleID: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app", shortcuts: presets)]
        return model
    }

    func testRenderAllIconAreas() throws {
        guard let folder else { throw XCTSkip("set BR_ICON_ALL_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = reviewModel()
        let sample = NamedShortcut.recommendedPresets[0]
        for dark in [false, true] {
            // Settings sidebar + pages.
            for (name, settingsPage) in [("settings-general", SettingsPage.general), ("settings-resolution", .resolution),
                                         ("settings-floating", .floating), ("settings-connection", .connection), ("settings-about", .about)] {
                try page(SettingsView(model: model, page: settingsPage)
                    .environment(\.settingsReview, SettingsReviewOverrides(version: "0.9.1 (196)")),
                         size: CGSize(width: 900, height: 980), dark: dark, name: name, in: folder)
            }
            try page(ScrollView { DeviceConfigurationSettings(model: model, deviceID: "uu:window:Phone") }.padding(24),
                     size: CGSize(width: 760, height: 1100), dark: dark, name: "device-detail", in: folder)
            try page(AutomaticResolutionSettings(model: model).environment(\.glassDropdownPreviewOpen, true).padding(24),
                     size: CGSize(width: 680, height: 560), dark: dark, name: "dropdown-open", in: folder)
            // Picker and forms.
            try page(BuiltinIconSheet(title: "复制", selected: ShortcutIcon.allCases[3], saveError: false, onCancel: {}, onPick: { _ in }),
                     size: CGSize(width: 520, height: 640), dark: dark, name: "icon-picker", in: folder)
            try page(ShortcutEditor(shortcut: sample, onSave: { _ in true }, onCancel: {}, onDelete: { true }),
                     size: CGSize(width: 560, height: 640), dark: dark, name: "form-shortcut-editor", in: folder)
            try page(SpecEditor(draft: SpecDraft(id: "review", name: "手机竖屏", width: "1080", height: "1920", isNew: true, scalePercent: 100),
                                onSave: { _ in }, onCancel: {}),
                     size: CGSize(width: 520, height: 420), dark: dark, name: "form-spec-editor", in: folder)
            try page(RecommendedPresetsView(model: model, permissions: .shared, close: {}),
                     size: CGSize(width: 560, height: 640), dark: dark, name: "form-presets", in: folder)
            try page(DeviceTemplatesView(model: model, close: {}).padding(20),
                     size: CGSize(width: 560, height: 520), dark: dark, name: "form-device-templates", in: folder)
            // Feedback, coffee, permission cards.
            try page(FeedbackFormView(model: FeedbackModel()).padding(20), size: CGSize(width: 460, height: 360), dark: dark, name: "card-feedback", in: folder)
            try page(CoffeeTipView().padding(20), size: CGSize(width: 360, height: 420), dark: dark, name: "card-coffee", in: folder)
            try page(PermissionGuideView(close: {}).frame(width: 390), size: CGSize(width: 430, height: 110), dark: dark, name: "card-permission", in: folder)
            // Top notice.
            try page(NoticeContent(title: "已切换到 1080 × 1920", detail: "断开连接后会自动恢复原分辨率").padding(16),
                     size: CGSize(width: 440, height: 100), dark: dark, name: "notice", in: folder)
            // Attached panels: the live blur cannot be captured offscreen, so they sit on the same opaque
            // surface LandingShots uses (pale grey light / window colour dark).
            let panelSurface = dark ? NSColor.windowBackgroundColor : NSColor(calibratedWhite: 0.94, alpha: 1)
            let panelWidth = DesktopToolbarLayout.resolutionPanel(to: CGRect(x: 1200, y: 0, width: 72, height: 640),
                                                                  in: CGRect(x: 0, y: 0, width: 1294, height: 640), presetCount: 10).width
            func panel<V: View>(_ content: V, size: CGSize, name: String) throws {
                let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(Color(nsColor: panelSurface)))
                host.frame = CGRect(origin: .zero, size: size)
                try render(host, size: size, dark: dark, background: panelSurface, to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
            try panel(ResolutionPanelView(model: model, close: {}), size: CGSize(width: panelWidth, height: 520), name: "panel-resolution")
            // 规格 picking grid with 立品's ten specs (factory + his own), shape and name only.
            let specModel = reviewModel()
            specModel.preferences.customPresets = [
                CustomPreset(id: "r1", name: "折叠屏(内)", width: 1080, height: 1000),
                CustomPreset.factorySpecs()[2], CustomPreset.factorySpecs()[0],
                CustomPreset(id: "r4", name: "平板横屏·4:3", width: 1024, height: 768),
                CustomPreset(id: "r5", name: "宽屏平板·16:10", width: 1280, height: 800),
                CustomPreset.factorySpecs()[3],
                CustomPreset(id: "r7", name: "iPhone Duo", width: 1206, height: 1310),
                CustomPreset.factorySpecs()[1],
                CustomPreset(id: "r9", name: "标准宽屏·16:9", width: 1280, height: 720),
                CustomPreset(id: "r10", name: "ThinkPad14", width: 1920, height: 1200)]
            try panel(ResolutionPanelView(model: specModel, close: {}), size: CGSize(width: panelWidth, height: 560), name: "spec-grid")
            let launcher = LauncherModel()
            launcher.error = "无法打开「示例」：应用已损坏"
            try panel(AppLauncherView(model: launcher), size: CGSize(width: 560, height: 300), name: "panel-apps")
            var preferences = Preferences()
            preferences.toolbarSide = .right
            let toolbar = FloatingSwitcher.reviewToolbar(preferences: preferences, in: CGRect(x: 0, y: 0, width: 1280, height: 720), hairline: true, backdrop: dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1))
            try render(toolbar, size: CGSize(width: toolbar.frame.width + 120, height: toolbar.frame.height + 40), dark: dark, background: .gray, colorful: true,
                       to: folder.appendingPathComponent("toolbar-\(dark ? "dark" : "light").png"))
        }
    }
}
