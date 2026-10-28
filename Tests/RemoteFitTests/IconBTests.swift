import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Style-B toolbar art: mapping and colour rules, plus offscreen sheets (only with BR_ICON_B_RENDER=<folder>).
@MainActor
final class IconBTests: XCTestCase {
    private let artKeys = ["spotlight", "paste", "copy", "switch-app", "desktop-left", "desktop-right", "return", "dock", "fill",
                           "minimize", "clear-desktop", "mission-control", "apps", "window-layout", "displays", "settings", "collapse"]

    func testEverySVGHasArtAndASymbol() {
        XCTAssertEqual(Set(BIcons.art.keys), Set(artKeys))
        XCTAssertEqual(Set(BIcons.keys.values), Set(artKeys))
        for action in FloatingAction.defaults { XCTAssertNotNil(BIcons.key(for: action.symbol), action.rawValue) }
        for side in ToolbarSide.allCases { XCTAssertEqual(BIcons.key(for: side.collapseSymbol), "collapse") }
        XCTAssertNotNil(BIcons.key(for: FloatingAction.settings.symbol))
        XCTAssertNotNil(BIcons.key(for: FloatingAction.resolution.symbol))
    }

    func testFillsStayWithinTheSpec() {
        for (key, layers) in BIcons.art {
            for layer in layers where layer.fill != nil {
                XCTAssertLessThanOrEqual(layer.fillOpacity, BIcons.maxFillOpacity, key)
            }
            XCTAssertTrue(layers.allSatisfy { $0.stroke == nil || $0.width >= 1.5 }, key)
        }
        // One accent hue per icon at most; the arrows carry none.
        for (key, layers) in BIcons.art {
            let hues = Set(layers.flatMap { [$0.stroke, $0.fill] }.compactMap { $0 }.filter { $0 != .fg })
            XCTAssertLessThanOrEqual(hues.count, 1, key)
            if ["desktop-left", "desktop-right", "return", "collapse"].contains(key) { XCTAssertTrue(hues.isEmpty, key) }
        }
        XCTAssertEqual(BIcons.art["minimize"]?.contains { $0.stroke == .orange }, true)
        XCTAssertEqual(BIcons.art["clear-desktop"]?.contains { $0.stroke == .green }, true)
    }

    func testSelectedArtIsWhiteOnly() throws {
        for dark in [false, true] {
            for symbol in ["text.magnifyingglass", "minus.rectangle", "rectangle.on.rectangle.slash", "gearshape"] {
                let image = try XCTUnwrap(BIcons.image(symbol, side: 23, style: .onAccent, dark: dark))
                let colours = try pixels(image)
                XCTAssertFalse(colours.isEmpty)
                for c in colours { XCTAssertEqual(c.r, c.g, accuracy: 0.02); XCTAssertEqual(c.g, c.b, accuracy: 0.02); XCTAssertGreaterThan(c.r, 0.97) }
            }
        }
    }

    func testNormalArtUsesTheSystemAccent() throws {
        let image = try XCTUnwrap(BIcons.image("square.grid.2x2", side: 24, style: .normal, dark: false))
        XCTAssertTrue(try pixels(image).contains { $0.b > $0.r + 0.3 })
        XCTAssertFalse(try XCTUnwrap(BIcons.image("arrow.left", side: 24, style: .normal, dark: false)).isTemplate)
        XCTAssertNil(BIcons.image("xmark", side: 24, style: .normal, dark: false))
    }

    /// Un-premultiplied colours of the visibly covered pixels.
    private func pixels(_ image: NSImage) throws -> [(r: CGFloat, g: CGFloat, b: CGFloat)] {
        let side = Int(image.size.width * 2)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        for x in 0..<side { for y in 0..<side {
            guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
            out.append((c.redComponent, c.greenComponent, c.blueComponent))
        } }
        return out
    }

    // MARK: - Offscreen sheets

    private var folder: URL? {
        ProcessInfo.processInfo.environment["BR_ICON_B_RENDER"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private let rows: [(String, String)] = [
        ("搜索 spotlight", "text.magnifyingglass"), ("粘贴 paste", "doc.on.clipboard"), ("复制 copy", "doc.on.doc"),
        ("切换应用 switch-app", "arrow.left.arrow.right"), ("左桌面 desktop-left", "arrow.left"), ("右桌面 desktop-right", "arrow.right"),
        ("回车 return", "return"), ("程序坞 dock", "dock.rectangle"), ("铺满 fill", "arrow.up.left.and.arrow.down.right.square"),
        ("最小化 minimize", "minus.rectangle"), ("清空桌面 clear-desktop", "rectangle.on.rectangle.slash"),
        ("调度中心 mission-control", "macwindow.on.rectangle"), ("应用 apps", "square.grid.2x2"), ("布局 window-layout", "rectangle.split.2x2"),
        ("分辨率 displays", "display.2"), ("设置 settings", "gearshape"),
        ("收起(右) collapse", "chevron.right.2"), ("收起(左)", "chevron.left.2"), ("收起(上)", "chevron.up.2"), ("收起(下)", "chevron.down.2"),
    ]

    func testRenderIconSheets() throws {
        guard let folder else { throw XCTSkip("set BR_ICON_B_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sizes: [CGFloat] = [18, 23, 28]
        let label: CGFloat = 170, cell: CGFloat = 46, rowH: CGFloat = 42, header: CGFloat = 40
        let columns = sizes.count * 2 + 1
        let size = CGSize(width: label + CGFloat(columns) * cell + 16, height: header + CGFloat(rows.count) * rowH + 12)
        for dark in [false, true] {
            let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            try writePNG(size: size, scale: 3, to: folder.appendingPathComponent("icons-\(dark ? "dark" : "light").png")) {
                appearance.performAsCurrentDrawingAppearance {
                    (dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
                    CGRect(origin: .zero, size: size).fill()
                    let text: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
                    var titles: [String] = []
                    for s in sizes { titles += ["\(Int(s))pt", "\(Int(s)) 选中"] }
                    titles.append("卡片选中")
                    for (i, t) in titles.enumerated() {
                        (t as NSString).draw(at: CGPoint(x: label + CGFloat(i) * cell + 4, y: size.height - 26), withAttributes: text)
                    }
                    for (r, row) in rows.enumerated() {
                        let y = size.height - header - CGFloat(r + 1) * rowH
                        (row.0 as NSString).draw(at: CGPoint(x: 10, y: y + 14), withAttributes: text)
                        for c in 0..<columns {
                            let point: CGFloat = c < sizes.count * 2 ? sizes[c / 2] : 18
                            let selected = c < sizes.count * 2 && c % 2 == 1
                            let card = c == sizes.count * 2
                            let centre = CGPoint(x: label + CGFloat(c) * cell + cell / 2, y: y + rowH / 2)
                            if selected || card {
                                let pad = CGRect(x: centre.x - 20, y: centre.y - 19, width: 40, height: 38)
                                (selected ? DesignTokens.NS.buttonActive : NSColor.controlBackgroundColor).setFill()
                                NSBezierPath(roundedRect: pad, xRadius: 8, yRadius: 8).fill()
                                if card { NSColor.systemBlue.setStroke(); let b = NSBezierPath(roundedRect: pad.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8); b.lineWidth = 1.5; b.stroke() }
                            }
                            let style: BIcons.Style = selected ? .onAccent : (card ? .selectedInCard : .normal)
                            guard let image = BIcons.image(row.1, side: point, style: style, dark: dark) else { continue }
                            image.draw(in: CGRect(x: centre.x - point / 2, y: centre.y - point / 2, width: point, height: point))
                        }
                    }
                }
            }
        }
    }

    /// The window-layout flyout (13 tiles) and the expanded toolbar on the new light surface.
    func testRenderLayoutFlyoutAndToolbar() throws {
        guard let folder else { throw XCTSkip("set BR_ICON_B_RENDER") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        var preferences = Preferences()
        preferences.toolbarSide = .right
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 640)
        for dark in [false, true] {
            let grey = dark ? NSColor(calibratedWhite: 0.32, alpha: 1) : NSColor(calibratedWhite: 0.78, alpha: 1)
            let both = FloatingSwitcher.reviewToolbarWithLayoutFlyout(preferences: preferences, in: visible)
            try renderInWindow(both, size: CGSize(width: both.frame.width + 80, height: both.frame.height + 40), dark: dark, background: grey,
                               to: folder.appendingPathComponent("toolbar-and-layout-flyout-\(dark ? "dark" : "light").png"))
        }
    }

    private func writePNG(size: CGSize, scale: CGFloat, to url: URL, draw: () -> Void) throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// Borderless window placed far off screen and never ordered front (no focus change).
    private func renderInWindow(_ view: NSView, size: CGSize, dark: Bool, background: NSColor, to url: URL) throws {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.appearance = window.appearance
        defer { NSApp.appearance = nil }
        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.wantsLayer = true
        window.appearance?.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = background.cgColor }
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
}
