import AppKit
import QuartzCore
import XCTest
@testable import RemoteFit

/// The bar/ball layer shadow must fade to nothing inside the transparent window padding, or the window edge
/// cuts it into a visible step (build 196: 14 / 0.22 → 4 / 0.10).
@MainActor
final class ToolbarShadowTests: XCTestCase {
    private static let glass = CGSize(width: 72, height: 240)

    /// Same shadow as FloatingSwitcher.paddedGlass, on a transparent window-sized canvas. CALayer.render(in:)
    /// drops layer shadows, so the shadow is drawn with Core Graphics using a blur of 2 × shadowRadius — at least
    /// as wide as the window server's, so this errs on the side of finding a cut-off.
    private func shadowLayer(radius: CGFloat, opacity: Float, circle: Bool = false) -> CALayer {
        let padding = FloatingSwitcher.glassPadding
        let size = circle ? CGSize(width: 56, height: 56) : Self.glass
        let container = ShadowCanvas()
        container.frame = CGRect(x: 0, y: 0, width: size.width + padding * 2, height: size.height + padding * 2)
        container.rect = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
        container.circle = circle
        container.radius = radius
        container.shadowAlpha = CGFloat(opacity)
        container.setNeedsDisplay()
        return container
    }

    private func bitmap(_ layer: CALayer, scale: CGFloat = 2) -> NSBitmapImageRep {
        let w = Int(layer.bounds.width * scale), h = Int(layer.bounds.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return rep
    }

    /// Strongest shadow alpha on the outermost pixel ring of the window (where the window edge would cut it).
    private func edgeAlpha(_ rep: NSBitmapImageRep) -> CGFloat {
        var maxAlpha: CGFloat = 0
        for x in 0..<rep.pixelsWide { for y in [0, rep.pixelsHigh - 1] { maxAlpha = max(maxAlpha, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
        for y in 0..<rep.pixelsHigh { for x in [0, rep.pixelsWide - 1] { maxAlpha = max(maxAlpha, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
        return maxAlpha
    }

    func testShadowFadesOutInsideTheWindowPaddingOnEveryEdge() {
        XCTAssertEqual(DesignTokens.toolbarShadowRadius, 4)
        XCTAssertEqual(DesignTokens.toolbarShadowOpacity, 0.10, accuracy: 0.001)
        XCTAssertLessThanOrEqual(DesignTokens.toolbarShadowRadius * 3 + abs(DesignTokens.toolbarShadowOffsetY), FloatingSwitcher.glassPadding)
        for circle in [false, true] {
            let rep = bitmap(shadowLayer(radius: DesignTokens.toolbarShadowRadius, opacity: DesignTokens.toolbarShadowOpacity, circle: circle))
            XCTAssertLessThanOrEqual(edgeAlpha(rep), 1.0 / 255, circle ? "ball" : "bar")
            // Still a shadow next to the glass.
            let near = rep.colorAt(x: Int(FloatingSwitcher.glassPadding * 2) - 3, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0
            XCTAssertGreaterThan(near, 0.01, circle ? "ball" : "bar")
        }
        // The old values reached the window edge: this is the step 立品 saw.
        XCTAssertGreaterThan(edgeAlpha(bitmap(shadowLayer(radius: 14, opacity: 0.22))), 2.0 / 255)
    }

    /// Enlarged edge of the bar over a warm wallpaper, light and dark, old vs new (BR_ICON_ALL_RENDER=<folder>).
    func testRenderShadowEdge() throws {
        guard let path = ProcessInfo.processInfo.environment["BR_ICON_ALL_RENDER"] else { throw XCTSkip("set BR_ICON_ALL_RENDER") }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let padding = FloatingSwitcher.glassPadding
        for dark in [false, true] {
            let surface = dark ? NSColor(calibratedRed: 30 / 255, green: 31 / 255, blue: 36 / 255, alpha: 0.62) : NSColor(calibratedWhite: 1, alpha: 0.62)
            let columns: [(String, CGFloat, Float)] = [("旧 14/0.22", 14, 0.22), ("新 4/0.10", DesignTokens.toolbarShadowRadius, DesignTokens.toolbarShadowOpacity)]
            let window = CGSize(width: Self.glass.width + padding * 2, height: Self.glass.height + padding * 2)
            let gap: CGFloat = 40
            let canvas = CALayer()
            canvas.frame = CGRect(x: 0, y: 0, width: (window.width + gap) * CGFloat(columns.count) + gap, height: window.height + gap * 2)
            let wallpaper = CAGradientLayer()
            wallpaper.frame = canvas.bounds
            wallpaper.colors = [NSColor.systemPink, .systemOrange, .systemYellow, .systemRed].map(\.cgColor)
            wallpaper.startPoint = .zero; wallpaper.endPoint = CGPoint(x: 1, y: 1)
            canvas.addSublayer(wallpaper)
            for (index, column) in columns.enumerated() {
                // The window clips everything it draws to its own frame.
                let clip = CALayer()
                clip.frame = CGRect(x: gap + CGFloat(index) * (window.width + gap), y: gap, width: window.width, height: window.height)
                clip.masksToBounds = true
                let shadow = shadowLayer(radius: column.1, opacity: column.2)
                clip.addSublayer(shadow)
                let glass = CALayer()
                glass.frame = CGRect(x: padding, y: padding, width: Self.glass.width, height: Self.glass.height)
                glass.cornerRadius = DesignTokens.radiusXl
                glass.backgroundColor = surface.cgColor
                glass.borderColor = (dark ? NSColor(calibratedWhite: 1, alpha: 0.12) : NSColor(calibratedWhite: 0, alpha: 0.12)).cgColor
                glass.borderWidth = 1
                clip.addSublayer(glass)
                canvas.addSublayer(clip)
                let label = CATextLayer()
                label.string = column.0; label.fontSize = 12; label.contentsScale = 4
                label.foregroundColor = NSColor.black.cgColor
                label.frame = CGRect(x: clip.frame.minX, y: 8, width: window.width + gap, height: 18)
                canvas.addSublayer(label)
            }
            let rep = bitmap(canvas, scale: 4)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: folder.appendingPathComponent("shadow-edge-\(dark ? "dark" : "light").png"))
        }
    }
}

private final class ShadowCanvas: CALayer {
    var rect = CGRect.zero, circle = false, radius: CGFloat = 0
    var shadowAlpha: CGFloat = 0

    override func draw(in ctx: CGContext) {
        let path = circle ? CGPath(ellipseIn: rect, transform: nil)
            : CGPath(roundedRect: rect, cornerWidth: DesignTokens.radiusXl, cornerHeight: DesignTokens.radiusXl, transform: nil)
        // Shadow only: draw the shape far off-canvas and throw its shadow back onto the canvas.
        let shift: CGFloat = 10_000
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: shift, height: DesignTokens.toolbarShadowOffsetY), blur: radius * 2,
                      color: NSColor.black.withAlphaComponent(shadowAlpha).cgColor)
        ctx.translateBy(x: -shift, y: 0)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
