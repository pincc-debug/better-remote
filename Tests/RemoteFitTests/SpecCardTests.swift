import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// 规格 picking grid in the toolbar's resolution panel: shape + name only, pixels in the hover tip (build 196).
@MainActor
final class SpecCardTests: XCTestCase {
    private static let landscape = CustomPreset.factorySpecs()[0]

    func testCardIs64PointsAndPixelsOnlyInTheHoverTip() {
        XCTAssertEqual(SpecCard.height, 64)
        XCTAssertEqual(SpecCard.help(Self.landscape), "1294 × 720")
        let host = NSHostingView(rootView: SpecCard(preset: Self.landscape, selected: false).frame(width: 150))
        XCTAssertEqual(host.fittingSize.height, 64, accuracy: 0.5)
    }

    /// One shape and one name line, centred: equal space above and below, no second text line.
    func testContentIsCentredWithNoSizeLine() throws {
        let width: CGFloat = 150
        let renderer = ImageRenderer(content: SpecCard(preset: Self.landscape, selected: false)
            .frame(width: width).environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let inset = 6 * 2
        let reference = try XCTUnwrap(rep.colorAt(x: inset, y: inset)?.usingColorSpace(.deviceRGB))
        func ink(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return abs(c.redComponent - reference.redComponent) + abs(c.greenComponent - reference.greenComponent)
                + abs(c.blueComponent - reference.blueComponent) + abs(c.alphaComponent - reference.alphaComponent) > 0.25
        }
        let rows = (inset..<(rep.pixelsHigh - inset)).filter { y in (inset..<(rep.pixelsWide - inset)).contains { ink($0, y) } }
        let top = try XCTUnwrap(rows.first), bottom = try XCTUnwrap(rows.last)
        let above = CGFloat(top) / 2, below = CGFloat(rep.pixelsHigh - 1 - bottom) / 2
        XCTAssertEqual(above, below, accuracy: 2.5, "shape+name centred (above \(above), below \(below))")
        // Shape (≤20) + gap + one 13pt line ≈ 42pt; a size line would add ~16pt.
        XCTAssertLessThan(CGFloat(bottom - top) / 2, 46, "only the shape and one line of name")
    }

    /// Built-in names (longest: 手机横屏（保留操作栏）) stay on one line at full 13pt in the 3-column wide panel (no wrap, no shrink).
    func testNamesFitWithoutShrinkingInTheWidePanel() {
        let panel = DesktopToolbarLayout.resolutionPanel(to: CGRect(x: 1200, y: 0, width: 72, height: 640),
                                                         in: CGRect(x: 0, y: 0, width: 1294, height: 640), presetCount: 7).width
        let content = min(panel - DesignTokens.spacingLg * 2, 500)
        XCTAssertEqual(max(1, min(3, Int((content + 16) / 110))), 3)
        let card = (content - DesignTokens.spacingSm * 2) / 3 - DesignTokens.spacingXs * 2
        let font = NSFont.systemFont(ofSize: DesignTokens.fontBody, weight: .medium)
        for preset in CustomPreset.factorySpecs() {
            let width = (preset.title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(width, card, "\(preset.title) \(width) > \(card)")
        }
    }
}
