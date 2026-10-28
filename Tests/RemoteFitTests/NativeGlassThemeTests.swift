import AppKit
import XCTest
@testable import RemoteFit

@MainActor
final class NativeGlassThemeTests: XCTestCase {
    func testSwitchingThemePreservesContentAndUpdatesBackdrop() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let glass = NativeGlassView(content: content, cornerRadius: 12, frame: content.frame,
                                    contentBackdrop: DesignTokens.NS.glassBackdrop)
        for _ in 0..<3 {
            glass.appearance = NSAppearance(named: .aqua)
            glass.layoutSubtreeIfNeeded()
            XCTAssertTrue(content.isDescendant(of: glass))
            XCTAssertTrue(content.superview is NSVisualEffectView)
            let light = try XCTUnwrap(content.layer?.backgroundColor)
            XCTAssertEqual(light.alpha, 0.06, accuracy: 0.01)
            glass.appearance = NSAppearance(named: .darkAqua)
            glass.layoutSubtreeIfNeeded()
            XCTAssertTrue(content.isDescendant(of: glass))
            let dark = try XCTUnwrap(content.layer?.backgroundColor)
            XCTAssertEqual(dark.alpha, 0.14, accuracy: 0.01)
            XCTAssertTrue(contentConstraintsRemainActive(in: glass, for: content))
        }
    }

    /// Toolbar surface: light mode fades only the blur (0.70), never the content above it; dark is untouched.
    func testLightBlurAlphaFadesOnlyTheBlur() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let glass = NativeGlassView(content: content, cornerRadius: 12, frame: content.frame,
                                    contentBackdrop: DesignTokens.NS.toolbarSurfaceBackdrop,
                                    lightBlurAlpha: DesignTokens.NS.toolbarLightBlurAlpha)
        XCTAssertEqual(DesignTokens.NS.toolbarLightBlurAlpha, 0.70, accuracy: 0.001)
        XCTAssertEqual(DesignTokens.NS.toolbarLightHairlineAlpha, 0.12, accuracy: 0.001)
        for _ in 0..<3 {
            glass.appearance = NSAppearance(named: .aqua)
            glass.layoutSubtreeIfNeeded()
            XCTAssertTrue(content.superview === glass)
            let blurs = glass.subviews.compactMap { $0 as? NSVisualEffectView }.filter { !$0.isHidden }
            XCTAssertEqual(blurs.count, 1)
            XCTAssertEqual(try XCTUnwrap(blurs.first).alphaValue, 0.70, accuracy: 0.001)
            XCTAssertEqual(content.alphaValue, 1)
            XCTAssertGreaterThan(try XCTUnwrap(glass.subviews.firstIndex(of: content)), try XCTUnwrap(glass.subviews.firstIndex(of: try XCTUnwrap(blurs.first))))
            XCTAssertEqual(try XCTUnwrap(content.layer?.backgroundColor).alpha, 0, accuracy: 0.001)
            XCTAssertTrue(contentConstraintsRemainActive(in: glass, for: content))
            glass.appearance = NSAppearance(named: .darkAqua)
            glass.layoutSubtreeIfNeeded()
            XCTAssertTrue(content.isDescendant(of: glass))
            XCTAssertFalse(content.superview === glass)
            XCTAssertTrue(glass.subviews.allSatisfy { $0.isHidden || $0.alphaValue == 1 })
            XCTAssertEqual(try XCTUnwrap(content.layer?.backgroundColor).alpha, 0.14, accuracy: 0.01)
            XCTAssertTrue(contentConstraintsRemainActive(in: glass, for: content))
        }
    }

    private func contentConstraintsRemainActive(in root: NSView, for content: NSView) -> Bool {
        guard let parent = content.superview else { return false }
        return parent.constraints.filter { $0.isActive && $0.firstItem as? NSView === content }.count == 4
    }
}
