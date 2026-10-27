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

    private func contentConstraintsRemainActive(in root: NSView, for content: NSView) -> Bool {
        guard let parent = content.superview else { return false }
        return parent.constraints.filter { $0.isActive && $0.firstItem as? NSView === content }.count == 4
    }
}
