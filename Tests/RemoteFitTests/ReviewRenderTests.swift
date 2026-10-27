import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Hairline geometry, plus offscreen review renders (only with BR_REVIEW_RENDER=<folder>; no window is ever shown).
@MainActor
final class ReviewRenderTests: XCTestCase {
    func testHairlineSkipsOnlyTheDockedEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 72, height: 400)
        let w: CGFloat = 0.5
        XCTAssertEqual(HairlineEdgeView.clip(bounds, omitting: .right, lineWidth: w), CGRect(x: 0, y: 0, width: 71.5, height: 400))
        XCTAssertEqual(HairlineEdgeView.clip(bounds, omitting: .left, lineWidth: w), CGRect(x: 0.5, y: 0, width: 71.5, height: 400))
        XCTAssertEqual(HairlineEdgeView.clip(bounds, omitting: .top, lineWidth: w), CGRect(x: 0, y: 0, width: 72, height: 399.5))
        XCTAssertEqual(HairlineEdgeView.clip(bounds, omitting: .bottom, lineWidth: w), CGRect(x: 0, y: 0.5, width: 72, height: 399.5))
        XCTAssertEqual(HairlineEdgeView.clip(bounds, omitting: nil, lineWidth: w), bounds)
        XCTAssertEqual(DesignTokens.hairline(scale: 2), 0.5)
        XCTAssertEqual(DesignTokens.hairline(scale: 1), 1)
    }

    private var folder: URL? {
        ProcessInfo.processInfo.environment["BR_REVIEW_RENDER"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Renders `view` in a borderless window that is never ordered on screen.
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
            gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
            root.layer?.addSublayer(gradient)
            for index in 0..<6 {
                let stripe = CATextLayer()
                stripe.string = "Better Remote 远程 \(index) ███ ▓▓▓ ░░░"
                stripe.fontSize = 22
                stripe.foregroundColor = (index.isMultiple(of: 2) ? NSColor.white : NSColor.black).cgColor
                stripe.frame = CGRect(x: 0, y: CGFloat(index) * size.height / 6, width: size.width, height: 30)
                root.layer?.addSublayer(stripe)
            }
        }
        view.frame.origin = CGPoint(x: (size.width - view.frame.width) / 2, y: (size.height - view.frame.height) / 2)
        root.addSubview(view)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        root.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }

    func testRenderToolbarEdges() throws {
        guard let folder = folder?.appendingPathComponent("toolbar-edge") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        var preferences = Preferences()
        preferences.toolbarSide = .right
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 640)
        for dark in [false, true] {
            for (name, hairline) in [("before", false), ("after", true)] {
                let view = FloatingSwitcher.reviewToolbar(preferences: preferences, in: visible, hairline: hairline)
                let bg = dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
                try render(view, size: CGSize(width: view.frame.width + 80, height: view.frame.height + 40), dark: dark, background: bg,
                           to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    func testRenderAutomationDropdown() throws {
        guard let folder = folder?.appendingPathComponent("dropdown") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = ControlPanelModel()
        var preferences = Preferences()
        preferences.setAutomaticResolutionEnabled(true)
        preferences.autoResolutionPresetID = preferences.customPresets.first?.id
        preferences.connectionDockMode = .alwaysShow // shows the 连接时的程序坞 caption
        model.preferences = preferences
        let size = CGSize(width: 640, height: 520)
        for dark in [false, true] {
            for open in [false, true] {
                let content = AutomaticResolutionSettings(model: model)
                    .environment(\.glassDropdownPreviewOpen, open)
                    .padding(DesignTokens.spacingXl)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(DesignTokens.Colors.pageBackground)
                let host = NSHostingView(rootView: content)
                host.frame = CGRect(origin: .zero, size: size)
                try render(host, size: size, dark: dark, background: .windowBackgroundColor,
                           to: folder.appendingPathComponent("\(open ? "open" : "closed")-\(dark ? "dark" : "light").png"))
            }
        }
    }

    func testRenderDeviceProfiles() throws {
        guard let folder = folder?.appendingPathComponent("device-profiles") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = ControlPanelModel()
        model.preferences.remoteDevices = [.init(id: "uu:window:Phone", name: "iPhone 13"), .init(id: "uu:window:Computer", name: "办公电脑")]
        model.preferences.customPresets += [CustomPreset(id: "review-phone", name: "手机竖屏", width: 1080, height: 1920),
                                           CustomPreset(id: "review-computer", name: "电脑横屏", width: 2560, height: 1600)]
        var phone = model.preferences.configuration(for: nil)
        phone.selectResolution("review-phone")
        model.preferences.setConfiguration(phone, for: "uu:window:Phone")
        var computer = model.preferences.configuration(for: nil)
        computer.selectResolution("review-computer")
        model.preferences.setConfiguration(computer, for: "uu:window:Computer")
        model.preferences.remoteDevices.append(.init(id: "uu:window:Disabled", name: "MacBook Pro", configurationEnabled: false))
        for dark in [false, true] {
            for width in [CGFloat(760), CGFloat(420)] {
                for state in ["list", "detail", "disabled"] {
                    let detail = state != "list"
                    let size = CGSize(width: width, height: 1100)
                    let content = Group {
                        if detail {
                            ScrollView { DeviceConfigurationSettings(model: model, deviceID: state == "disabled" ? "uu:window:Disabled" : "uu:window:Computer") }
                        } else {
                            DeviceListSettings(model: model)
                        }
                    }.padding(24).environment(\.settingsNarrow, width < 500)
                        .frame(width: size.width, height: size.height)
                        .background(DesignTokens.Colors.pageBackground)
                    let host = NSHostingView(rootView: content)
                    host.frame = CGRect(origin: .zero, size: size)
                    try render(host, size: size, dark: dark, background: .windowBackgroundColor,
                               to: folder.appendingPathComponent("\(state)-\(Int(width))-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }

    func testRenderUpdatedSettingsPages() throws {
        guard let folder = folder?.appendingPathComponent("updated-settings") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = ControlPanelModel()
        model.preferences.remember(.init(id: "uu:window:vivoV2545A", name: "vivoV2545A"))
        model.preferences.renameDevice("uu:window:vivoV2545A", to: "我的手机")
        for (name, page) in [("devices", SettingsPage.connection), ("general", SettingsPage.general), ("about", SettingsPage.about)] {
            let size = CGSize(width: 880, height: 720)
            let content = SettingsView(model: model, page: page)
                .environment(\.settingsReview, SettingsReviewOverrides(version: "0.8.169-test"))
                .frame(width: size.width, height: size.height)
                .background(DesignTokens.Colors.pageBackground)
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(origin: .zero, size: size)
            try render(host, size: size, dark: true, background: .windowBackgroundColor,
                       to: folder.appendingPathComponent("\(name).png"))
        }
    }

    func testRenderToolbarGlass() throws {
        guard let folder = folder?.appendingPathComponent("toolbar-glass") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        var preferences = Preferences()
        preferences.toolbarSide = .right
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 640)
        // The 0.8.138 tint, for comparison.
        let previous = NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0, alpha: 0.36) : NSColor(calibratedWhite: 1, alpha: 0.18) }
        for dark in [false, true] {
            for colorful in [false, true] {
                for (name, backdrop, hairline) in [("before", previous, false), ("after", DesignTokens.NS.glassBackdrop, true)] {
                    let view = FloatingSwitcher.reviewToolbar(preferences: preferences, in: visible, hairline: hairline, backdrop: backdrop)
                    let grey = dark ? NSColor(calibratedWhite: 0.32, alpha: 1) : NSColor(calibratedWhite: 0.78, alpha: 1)
                    try render(view, size: CGSize(width: view.frame.width + 160, height: view.frame.height + 40), dark: dark, background: grey, colorful: colorful,
                               to: folder.appendingPathComponent("\(name)-\(colorful ? "colorful" : "grey")-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }

    /// The 规格 card grid of the resolution panel, light mode: the full three-column width and the width it gets on a portrait-phone desktop.
    func testRenderPresetCards() throws {
        guard let folder = folder?.appendingPathComponent("preset-cards") else { throw XCTSkip("set BR_REVIEW_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = ControlPanelModel()
        model.preferences = Preferences()
        let font = NSFont.systemFont(ofSize: DesignTokens.fontBody, weight: .medium)
        for preset in model.preferences.customPresets {
            let width = (preset.title as NSString).size(withAttributes: [.font: font]).width
            print("BR_TITLE_WIDTH \(preset.title) \(Int(width.rounded(.up)))pt")
        }
        let full = DesktopToolbarLayout.resolutionPanel(to: CGRect(x: 1200, y: 0, width: 72, height: 640),
                                                        in: CGRect(x: 0, y: 0, width: 1294, height: 640), presetCount: 7).width
        // Docked on the right of a 604-point-wide portrait-phone desktop.
        let portrait = DesktopToolbarLayout.resolutionPanel(to: CGRect(x: 604 - 72, y: 0, width: 72, height: 1000),
                                                            in: CGRect(x: 0, y: 0, width: 604, height: 1138), presetCount: 7).width
        for (name, width) in [("wide", full), ("portrait-phone", portrait)] {
            let size = CGSize(width: width, height: 560)
            let content = ResolutionPanelView(model: model, close: {})
                .frame(width: size.width, height: size.height)
                .background(DesignTokens.Colors.pageBackground)
            let host = NSHostingView(rootView: content)
            host.frame = CGRect(origin: .zero, size: size)
            try render(host, size: size, dark: false, background: .windowBackgroundColor,
                       to: folder.appendingPathComponent("\(name)-light.png"))
            print("BR_PANEL \(name) \(Int(width))pt")
        }
    }
}
