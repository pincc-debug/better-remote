import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Review renders of 设置 and its sheets at desktop and phone-portrait sizes (only with BR_SETTINGS_SHOTS=<folder>).
/// Offscreen, never ordered on screen; built-in sample data only, saved preferences untouched.
@MainActor
final class NarrowSettingsShotsTests: XCTestCase {
    private final class ActiveOffscreenWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    private var folder: URL? {
        ProcessInfo.processInfo.environment["BR_SETTINGS_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func sampleModel() -> ControlPanelModel {
        let model = ControlPanelModel()
        var p = Preferences()
        p.autoResolutionEnabled = true
        p.connectionDockMode = .alwaysShow
        model.preferences = p
        return model
    }

    /// Renders `root` at `size`, or at its fitting size (re-measured until stable) when `size` is nil.
    private func render<V: View>(_ root: V, size: CGSize?, to name: String) throws -> CGSize {
        let folder = try XCTUnwrap(folder)
        let view = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        let start = size ?? CGSize(width: 1000, height: 1000)
        let window = ActiveOffscreenWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: start), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: size ?? view.fittingSize)
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            if size == nil { view.frame.size = view.fittingSize }
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
        window.close()
        print("BR_SHOT \(name) \(Int(view.frame.width))x\(Int(view.frame.height))pt")
        return view.frame.size
    }

    func testRenderSettingsAtDesktopAndPhoneWidths() throws {
        guard let folder else { throw XCTSkip("BR_SETTINGS_SHOTS not set") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = sampleModel()
        // 360 is the minimum window width; a 430 pt wide phone-portrait screen gives a 406 pt window.
        let phone = SettingsWindowLayout.frameSize(in: CGRect(x: 0, y: 0, width: 430, height: 900))
        let sizes: [(String, CGSize)] = [("desktop", SettingsWindowLayout.preferredSize), ("w406", CGSize(width: phone.width, height: 720)),
                                         ("w360", CGSize(width: SettingsWindowLayout.minimumSize.width, height: 720))]
        for (name, size) in sizes {
            for page in [SettingsPage.general, .connection, .floating, .resolution, .touch, .about] {
                _ = try render(SettingsView(model: model, page: page)
                    .environment(\.settingsReview, SettingsReviewOverrides(version: "0.8.147"))
                    .frame(width: size.width, height: size.height), size: size, to: "settings-\(name)-\(page)")
            }
        }
    }

    func testRenderDeviceResolutionSettings() throws {
        guard let folder else { throw XCTSkip("BR_SETTINGS_SHOTS not set") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = sampleModel()
        for populated in [false, true] {
            model.preferences.remoteDevices = populated ? [
                .init(id: "uu:phone", name: "vivoV2545A"),
                .init(id: "uu:tablet", name: "iPad Pro", presetID: model.preferences.autoResolutionPresetID)
            ] : []
            for width in [760.0, 360.0] {
                _ = try render(SettingsView(model: model, page: .connection)
                    .environment(\.settingsReview, SettingsReviewOverrides(version: "0.8.152"))
                    .frame(width: width, height: 820), size: CGSize(width: width, height: 820),
                    to: "devices-\(populated ? "populated" : "empty")-\(Int(width))")
            }
        }
        model.preferences.autoResolutionEnabled = false
        _ = try render(SettingsView(model: model, page: .connection)
            .frame(width: 760, height: 820), size: CGSize(width: 760, height: 820), to: "devices-main-off")
    }

    func testRenderSheetsAtDesktopAndPhoneLimits() throws {
        guard let folder else { throw XCTSkip("BR_SETTINGS_SHOTS not set") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = sampleModel()
        // Limits = screen visible area minus 16 per side: desktop, 430 and 384 pt wide phones, and a short screen.
        let limits: [(String, CGSize)] = [
            ("desktop", SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 0, width: 1728, height: 1084))),
            ("w406", SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 0, width: 430, height: 900))),
            ("w360", SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 0, width: 384, height: 900))),
            ("short", SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 0, width: 430, height: 280))),
        ]
        let shortcut = NamedShortcut(name: "复制", key: ShortcutKey(code: 8, modifiers: 1 << 20, label: "C"))
        for (name, limit) in limits {
            func shot<V: View>(_ view: V, _ dialog: String) throws {
                let size = try render(view.environment(\.dialogLimitOverride, limit), size: nil, to: "sheet-\(name)-\(dialog)")
                XCTAssertLessThanOrEqual(size.width, limit.width + 0.5, dialog)
                XCTAssertLessThanOrEqual(size.height, limit.height + 0.5, dialog)
            }
            try shot(ShortcutEditor(shortcut: shortcut, onSave: { _ in true }, onCancel: {}), "shortcut-editor")
            try shot(SpecEditor(draft: .adding(dimensions: model.preferences.dimensions), onSave: { _ in }, onCancel: {}), "spec-editor")
            try shot(DeviceTemplatesView(model: model, close: {}), "device-templates")
            try shot(RecommendedPresetsView(model: model, permissions: .shared, close: {}), "recommended-presets")
            try shot(BuiltinIconSheet(title: "应用", selected: .copy, saveError: false, onCancel: {}, onPick: { _ in }), "builtin-icon")
        }
    }
}
