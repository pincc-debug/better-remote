import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Where the toolbar window goes (0.9.2): the glass fills its dock edge of the visible frame and the window keeps
/// 16pt of shadow room only toward the desktop, so macOS has no reason to push it out of the menu bar / Dock.
@MainActor
final class ToolbarPlacementTests: XCTestCase {
    static let screen = CGRect(x: 0, y: 0, width: 1138, height: 1051)
    static let dockShown = CGRect(x: 0, y: 51, width: 1138, height: 970)
    static let dockHidden = CGRect(x: 0, y: 0, width: 1138, height: 1021)
    static let padding = FloatingSwitcher.glassPadding

    private func expanded(_ side: ToolbarSide, in visible: CGRect) -> CGRect {
        DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: true, count: 6, side: side)
    }

    func testExpandedBarFillsItsDockEdgeAndKeepsShadowRoomOnlyTowardTheDesktop() {
        for visible in [Self.dockShown, Self.dockHidden] {
            for side in ToolbarSide.allCases {
                let glass = expanded(side, in: visible)
                let placement = FloatingSwitcher.panelPlacement(glass: glass, in: visible)
                let name = "\(side) \(visible)"
                // The window never reaches into the menu bar, the Dock or past the screen edge.
                XCTAssertTrue(visible.contains(placement.frame), name)
                // The glass inside the window is exactly the reserved strip (same rect the window layout avoids).
                XCTAssertEqual(FloatingSwitcher.glassFrame(inPanel: placement.frame, insets: placement.insets), glass, name)
                XCTAssertEqual(glass, DesktopToolbarLayout.toolbar(in: visible, centerY: 0, expanded: true, count: 6, side: side), name)
                let i = placement.insets
                switch side {
                case .right:
                    XCTAssertEqual(glass.maxY, visible.maxY, name); XCTAssertEqual(glass.minY, visible.minY, name); XCTAssertEqual(glass.maxX, visible.maxX, name)
                    XCTAssertEqual([i.left, i.right, i.top, i.bottom], [Self.padding, 0, 0, 0], name)
                case .left:
                    XCTAssertEqual(glass.maxY, visible.maxY, name); XCTAssertEqual(glass.minY, visible.minY, name); XCTAssertEqual(glass.minX, visible.minX, name)
                    XCTAssertEqual([i.left, i.right, i.top, i.bottom], [0, Self.padding, 0, 0], name)
                case .top:
                    XCTAssertEqual(glass.maxY, visible.maxY, name); XCTAssertEqual(glass.width, visible.width, name)
                    XCTAssertEqual([i.left, i.right, i.top, i.bottom], [0, 0, 0, Self.padding], name)
                case .bottom:
                    XCTAssertEqual(glass.minY, visible.minY, name); XCTAssertEqual(glass.width, visible.width, name)
                    XCTAssertEqual([i.left, i.right, i.top, i.bottom], [0, 0, Self.padding, 0], name)
                }
                // The room toward the desktop is enough for the whole shadow (radius × 3 + offset).
                XCTAssertGreaterThanOrEqual(Self.padding, DesignTokens.toolbarShadowRadius * 3 + abs(DesignTokens.toolbarShadowOffsetY))
            }
        }
    }

    /// 0.9.1 for comparison: 16pt on every edge put the right bar's window 16pt into the menu bar.
    func testOldUniformPaddingReachedIntoTheMenuBar() {
        let glass = expanded(.right, in: Self.dockShown)
        let old = glass.insetBy(dx: -Self.padding, dy: -Self.padding)
        XCTAssertEqual(old.maxY - Self.dockShown.maxY, Self.padding)
        XCTAssertFalse(Self.dockShown.contains(old))
    }

    func testBallKeepsShadowRoomTowardTheDesktopAndNeverLeavesTheVisibleFrame() {
        let margin = DesktopToolbarLayout.margin
        for visible in [Self.dockShown, Self.dockHidden] {
            let ball = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: false, count: 0)
            for y in [visible.minY + margin, visible.minY + 40, visible.midY, visible.maxY - ball.height - margin] {
                let glass = CGRect(x: ball.minX, y: y, width: ball.width, height: ball.height)
                let placement = FloatingSwitcher.panelPlacement(glass: glass, in: visible)
                let i = placement.insets
                XCTAssertTrue(visible.contains(placement.frame), "\(y)")
                XCTAssertEqual(FloatingSwitcher.glassFrame(inPanel: placement.frame, insets: i), glass)
                XCTAssertEqual(i.left, Self.padding) // toward the desktop
                XCTAssertEqual(i.right, margin)       // up to the screen edge
                XCTAssertEqual(i.top, min(Self.padding, visible.maxY - glass.maxY))
                XCTAssertEqual(i.bottom, min(Self.padding, glass.minY - visible.minY))
            }
        }
    }

    // MARK: - Offscreen renders (BR_PLACEMENT_RENDER=<folder>; no window is ever shown)

    func testRenderPlacements() throws {
        guard let path = ProcessInfo.processInfo.environment["BR_PLACEMENT_RENDER"] else { throw XCTSkip("set BR_PLACEMENT_RENDER") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for (dockName, visible) in [("dock-shown", Self.dockShown), ("dock-hidden", Self.dockHidden)] {
            for side in ToolbarSide.allCases {
                var preferences = Preferences()
                preferences.toolbarSide = side
                let glass = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: true, count: preferences.enabledOperations.count,
                                                         side: side, windowControls: preferences.showWindowControls)
                let bar = FloatingSwitcher.reviewToolbar(preferences: preferences, in: visible, hairline: true)
                try render(name: "\(side)-\(dockName)", glass: glass, glassView: bar, side: side, visible: visible, circle: false, folder: folder)
            }
            let ball = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: false, count: 0)
            for (name, y) in [("bottom", ball.minY), ("top", visible.maxY - ball.height - DesktopToolbarLayout.margin)] {
                let glass = CGRect(x: ball.minX, y: y, width: ball.width, height: ball.height)
                let view = NSView(frame: CGRect(origin: .zero, size: glass.insetBy(dx: -Self.padding, dy: -Self.padding).size))
                let surface = NSView(frame: CGRect(origin: CGPoint(x: Self.padding, y: Self.padding), size: glass.size))
                surface.wantsLayer = true
                surface.layer?.cornerRadius = glass.width / 2
                surface.layer?.backgroundColor = DesignTokens.NS.toolbarSurfaceBackdrop.cgColor
                view.addSubview(surface)
                try render(name: "ball-\(name)-\(dockName)", glass: glass, glassView: view, side: .right, visible: visible, circle: true, folder: folder)
            }
        }
    }

    /// `glassView` carries the glass at (padding, padding), like `FloatingSwitcher.reviewToolbar`.
    private func render(name: String, glass: CGRect, glassView: NSView, side: ToolbarSide, visible: CGRect, circle: Bool, folder: URL) throws {
        let screen = Self.screen
        let placement = FloatingSwitcher.panelPlacement(glass: glass, in: visible)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -40_000, y: -40_000), size: screen.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let root = SceneView(frame: CGRect(origin: .zero, size: screen.size))
        root.visible = visible
        root.workspace = circle ? visible : DesktopToolbarLayout.workspace(avoiding: glass, in: visible, side: side)
        // The toolbar window: it clips everything (shadow included) to its own frame.
        let clip = NSView(frame: placement.frame)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        let shadow = ShadowView(frame: clip.bounds)
        shadow.glass = glass.offsetBy(dx: -placement.frame.minX, dy: -placement.frame.minY)
        shadow.circle = circle
        clip.addSubview(shadow)
        glassView.frame.origin = CGPoint(x: glass.minX - Self.padding - placement.frame.minX, y: glass.minY - Self.padding - placement.frame.minY)
        clip.addSubview(glassView)
        root.addSubview(clip)
        let overlay = OverlayView(frame: root.bounds)
        overlay.visible = visible
        overlay.panel = placement.frame
        overlay.caption = "\(name)  visible \(NSStringFromRect(visible))  window \(NSStringFromRect(placement.frame))  glass \(NSStringFromRect(glass))"
        root.addSubview(overlay)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        root.layoutSubtreeIfNeeded()
        try snapshot(root, rect: root.bounds, scale: 2, to: folder.appendingPathComponent("\(name).png"))
        // Close-ups of both ends of the bar (or around the ball) where it meets the menu bar / Dock / screen edge.
        let crops: [(String, CGRect)]
        if circle {
            crops = [("zoom", glass.insetBy(dx: -40, dy: -40))]
        } else if side.isHorizontal {
            crops = [("zoom-left", CGRect(x: glass.minX, y: glass.midY - 70, width: 200, height: 140)),
                     ("zoom-right", CGRect(x: glass.maxX - 200, y: glass.midY - 70, width: 200, height: 140))]
        } else {
            let x = side == .right ? glass.maxX - 170 : glass.minX
            crops = [("zoom-top", CGRect(x: x, y: glass.maxY - 90, width: 170, height: 140)),
                     ("zoom-bottom", CGRect(x: x, y: glass.minY - 50, width: 170, height: 140))]
        }
        for (suffix, rect) in crops {
            try snapshot(root, rect: rect.intersection(root.bounds), scale: 6, to: folder.appendingPathComponent("\(name)-\(suffix).png"))
        }
        window.close()
    }

    private func snapshot(_ view: NSView, rect: CGRect, scale: CGFloat, to url: URL) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * scale), pixelsHigh: Int(rect.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    // MARK: - Window server probe (BR_WINDOW_CLAMP_PROBE=<file>)

    /// Orders a fully transparent, click-through panel for about two seconds and reads back where the window server
    /// put it: once with 0.9.1's geometry (16pt into the menu bar) and once with 0.9.2's. Touches no input devices.
    func testWindowServerClampProbe() throws {
        guard let path = ProcessInfo.processInfo.environment["BR_WINDOW_CLAMP_PROBE"] else { throw XCTSkip("set BR_WINDOW_CLAMP_PROBE") }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let glass = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: true, count: 6, side: .right)
        let old = glass.insetBy(dx: -Self.padding, dy: -Self.padding)
        let new = FloatingSwitcher.panelPlacement(glass: glass, in: visible).frame
        var lines = ["screen \(NSStringFromRect(screen.frame)) visible \(NSStringFromRect(visible)) glass \(NSStringFromRect(glass))"]
        var newActual = CGRect.zero
        for (name, target) in [("0.9.1-uniform", old), ("0.9.2-per-edge", new)] {
            let panel = NSPanel(contentRect: target, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.setFrame(target, display: false)
            panel.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            panel.setFrame(target, display: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(panel.windowNumber)) as? [[String: Any]])?.first
            let bounds = (info?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            lines.append("\(name) target \(NSStringFromRect(target)) panel.frame \(NSStringFromRect(panel.frame)) CG \(bounds.map { NSStringFromRect($0) } ?? "nil")")
            if name.hasPrefix("0.9.2") { newActual = panel.frame }
            panel.orderOut(nil)
            panel.close()
        }
        let text = lines.joined(separator: "\n") + "\n"
        print(text)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(newActual, new)
    }
}

/// Wallpaper and a stand-in for the laid-out app window (the workspace the toolbar leaves free).
private final class SceneView: NSView {
    var visible = CGRect.zero, workspace = CGRect.zero
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [.systemTeal, .systemBlue, .systemPurple, .systemPink])!
        gradient.draw(in: bounds, angle: -60)
        let window = NSBezierPath(roundedRect: workspace, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); window.fill()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: workspace.minX, y: workspace.maxY - 28, width: workspace.width, height: 28)).fill()
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke(); window.lineWidth = 1; window.stroke()
        ("全屏窗口（工作区）" as NSString).draw(at: CGPoint(x: workspace.minX + 80, y: workspace.maxY - 21),
                                         withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
    }
}

/// Same shadow as FloatingSwitcher.paddedGlass (blur 2 × radius, at least as wide as the window server's).
private final class ShadowView: NSView {
    var glass = CGRect.zero, circle = false
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let path = circle ? CGPath(ellipseIn: glass, transform: nil)
                          : CGPath(roundedRect: glass, cornerWidth: DesignTokens.radiusXl, cornerHeight: DesignTokens.radiusXl, transform: nil)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setShadow(offset: CGSize(width: 0, height: DesignTokens.toolbarShadowOffsetY), blur: DesignTokens.toolbarShadowRadius * 2,
                          color: NSColor.black.withAlphaComponent(CGFloat(DesignTokens.toolbarShadowOpacity)).cgColor)
        context.addPath(path); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.clear)
        context.addPath(path); context.fillPath()
        context.endTransparencyLayer()
    }
}

/// Menu bar, Dock, the visible frame's edges (cyan) and the toolbar window's outline (red, dashed).
private final class OverlayView: NSView {
    var visible = CGRect.zero, panel = CGRect.zero, caption = ""
    override func draw(_ dirtyRect: NSRect) {
        let menu = CGRect(x: bounds.minX, y: 1021, width: bounds.width, height: bounds.height - 1021)
        NSColor(calibratedWhite: 0.92, alpha: 0.96).setFill(); NSBezierPath(rect: menu).fill()
        ("  菜单栏" as NSString).draw(at: CGPoint(x: 8, y: menu.minY + 8), withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        if visible.minY > 0 {
            let dock = CGRect(x: bounds.midX - 360, y: 2, width: 720, height: visible.minY - 4)
            NSColor(calibratedWhite: 0.95, alpha: 0.75).setFill(); NSBezierPath(roundedRect: dock, xRadius: 16, yRadius: 16).fill()
            ("程序坞" as NSString).draw(at: CGPoint(x: dock.midX - 20, y: dock.midY - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        }
        NSColor.systemCyan.setStroke()
        for y in [visible.minY, visible.maxY] {
            let line = NSBezierPath(); line.move(to: CGPoint(x: 0, y: y)); line.line(to: CGPoint(x: bounds.maxX, y: y))
            line.lineWidth = 0.5; line.setLineDash([2, 2], count: 2, phase: 0); line.stroke()
        }
        let outline = NSBezierPath(rect: panel.insetBy(dx: 0.25, dy: 0.25))
        outline.lineWidth = 0.5; outline.setLineDash([3, 2], count: 2, phase: 0)
        NSColor.systemRed.setStroke(); outline.stroke()
        (caption as NSString).draw(in: CGRect(x: 160, y: 520, width: 640, height: 60),
                                   withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.black])
    }
}
