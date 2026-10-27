import AppKit
import ObjectiveC
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Landing-page screenshots, 2x PNG, rendered offscreen (only with BR_LANDING_SHOTS=<folder>; no window is shown,
/// the installed app and saved preferences are never touched). Built-in sample data only.
/// Reports itself key and main so controls draw in their active (accent) state; it is never ordered on screen.
private final class ActiveOffscreenWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor
final class LandingShotsTests: XCTestCase {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["BR_LANDING_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Frosted stand-in for system glass, which cannot be captured offscreen.
    private static let frosted = NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(calibratedRed: 30 / 255, green: 31 / 255, blue: 36 / 255, alpha: 0.62) : NSColor(calibratedWhite: 1, alpha: 0.62) }

    private func sampleModel() -> ControlPanelModel {
        let model = ControlPanelModel()
        var p = Preferences()
        p.selectedCustomID = CustomPreset.recommendedLandscapeID
        p.autoResolutionPresetID = CustomPreset.recommendedLandscapeID
        p.autoResolutionEnabled = true
        p.autoRestoreOnDisconnect = true
        p.autoFillWindowsOnRemote = true
        p.connectionDockMode = .keep
        p.toolbarSide = .right
        model.preferences = p
        model.applied = p.dimensions
        model.adjustment = ResolutionAdjustment(p.dimensions)
        return model
    }

    private func render(_ view: NSView, size: CGSize, dark: Bool, background: NSColor?, to url: URL) throws {
        let window = ActiveOffscreenWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = window.appearance
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        window.appearance?.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = (background ?? .clear).cgColor }
        view.frame.origin = CGPoint(x: (size.width - view.frame.width) / 2, y: (size.height - view.frame.height) / 2)
        root.addSubview(view)
        window.contentView = root
        for _ in 0..<2 { root.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        let scale: CGFloat = 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }

    func testLandingShots() throws {
        guard let folder else { throw XCTSkip("set BR_LANDING_SHOTS") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        // Controls draw inactive (grey) while the test runner is in the background; report this process active
        // for the duration of the renders only, without activating it or showing anything.
        let selector = NSSelectorFromString("isActive")
        let method = try XCTUnwrap(class_getInstanceMethod(NSApplication.self, selector))
        let original = method_getImplementation(method)
        let alwaysActive: @convention(block) (AnyObject) -> Bool = { _ in true }
        method_setImplementation(method, imp_implementationWithBlock(alwaysActive))
        defer { method_setImplementation(method, original) }
        // Same idea for the window's active-appearance queries the switch track consults.
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        for name in ["_hasActiveAppearance", "_hasActiveAppearanceIgnoringKeyFocus", "_hasKeyAppearance", "hasKeyAppearance", "hasMainAppearance", "hasActiveAppearance"] {
            let sel = NSSelectorFromString(name)
            if class_getInstanceMethod(NSWindow.self, sel) != nil {
                class_addMethod(ActiveOffscreenWindow.self, sel, imp_implementationWithBlock(yes), "c@:")
                print("BR_OVERRIDE \(name)")
            }
        }
        // The app icon for the settings sidebar, from the locally built bundle when present.
        let icns = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dist/Better Remote.app/Contents/Resources/AppIcon.icns")
        if NSImage(named: "AppIcon") == nil, let icon = NSImage(contentsOf: icns) { icon.setName("AppIcon") }

        defer { NSApp.appearance = nil }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            // Views resolve their layer colours when built, so pick the appearance first.
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

            // 1. Resolution panel (opaque rectangle; the composer rounds and shadows it).
            let model = sampleModel()
            var contentHeight: CGFloat = 0
            let panelWidth = DesktopToolbarLayout.resolutionPanel(to: CGRect(x: 1200, y: 0, width: 72, height: 640),
                                                                  in: CGRect(x: 0, y: 0, width: 1294, height: 640), presetCount: 7).width
            let probe = NSHostingView(rootView: ResolutionPanelView(model: model, close: {}, onContentHeight: { contentHeight = $0 })
                .frame(width: panelWidth, height: 900))
            probe.frame = CGRect(x: 0, y: 0, width: panelWidth, height: 900)
            try render(probe, size: probe.frame.size, dark: dark, background: .windowBackgroundColor,
                       to: folder.appendingPathComponent(".probe.png"))
            let height = contentHeight > 0 ? contentHeight : 460
            // Light glass reads as a pale grey over the desktop, so the white cards stay visible; dark uses the window colour.
            let panelSurface = dark ? NSColor.windowBackgroundColor : NSColor(calibratedWhite: 0.94, alpha: 1)
            let panel = NSHostingView(rootView: ResolutionPanelView(model: model, close: {})
                .frame(width: panelWidth, height: height).background(Color(nsColor: panelSurface)))
            panel.frame = CGRect(x: 0, y: 0, width: panelWidth, height: height)
            try render(panel, size: panel.frame.size, dark: dark, background: panelSurface,
                       to: folder.appendingPathComponent("presets-\(theme).png"))
            print("BR_SHOT presets-\(theme) \(Int(panelWidth))x\(Int(height))pt")

            // 2. Settings window on 连接自动化, with the sidebar.
            let settingsSize = CGSize(width: 900, height: 620)
            let settings = NSHostingView(rootView: SettingsView(model: sampleModel(), page: .connection)
                .environment(\.settingsReview, SettingsReviewOverrides(version: "0.8.143"))
                .environment(\.controlActiveState, .key)
                .frame(width: settingsSize.width, height: settingsSize.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            settings.frame = CGRect(origin: .zero, size: settingsSize)
            try render(settings, size: settingsSize, dark: dark, background: .windowBackgroundColor,
                       to: folder.appendingPathComponent("automation-\(theme).png"))

            // 3. Right-docked expanded toolbar, transparent around it.
            var prefs = Preferences(); prefs.toolbarSide = .right
            let bar = FloatingSwitcher.reviewToolbar(preferences: prefs, in: CGRect(x: 0, y: 0, width: 1294, height: 720), hairline: true, backdrop: Self.frosted)
            try render(bar, size: bar.frame.size, dark: dark, background: nil, to: folder.appendingPathComponent("toolbar-\(theme).png"))
            print("BR_SHOT toolbar-\(theme) \(Int(bar.frame.width))x\(Int(bar.frame.height))pt")

            // 4. Window-layout flyout on its own, and open beside the right-docked bar as in the product.
            let flyout = FloatingSwitcher.reviewLayoutFlyout(backdrop: Self.frosted)
            try render(flyout, size: flyout.frame.size, dark: dark, background: nil, to: folder.appendingPathComponent("layouts-\(theme).png"))
            let attached = FloatingSwitcher.reviewToolbarWithLayoutFlyout(preferences: prefs, in: CGRect(x: 0, y: 0, width: 1294, height: 720), backdrop: Self.frosted)
            try render(attached, size: attached.frame.size, dark: dark, background: nil,
                       to: folder.appendingPathComponent("toolbar-layouts-attached-\(theme).png"))
            print("BR_SHOT toolbar-layouts-attached-\(theme) \(Int(attached.frame.width))x\(Int(attached.frame.height))pt")
        }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(".probe.png"))
    }
}
