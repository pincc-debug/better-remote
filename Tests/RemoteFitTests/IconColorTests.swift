import AppKit
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// App-wide icon colouring (icon-color-rules.md): which icons are layered, whole blue or single-colour, and the
/// selection / blur constants that go with them.
@MainActor
final class IconColorTests: XCTestCase {
    private let forcedWholeBlue = ["hand.draw", "hand.tap.fill", "lightbulb.fill", "speaker.wave.1.fill"]

    func testWholeBlueSetIsTheReviewedList() {
        XCTAssertEqual(IconArt.wholeBlueSymbols.count, 140)
        for name in forcedWholeBlue { XCTAssertTrue(IconArt.isWholeBlue(name), name) }
        XCTAssertFalse(IconArt.wholeBlueSymbols.contains("magnet"), "magnet does not exist on macOS 14; functional todo")
        for name in IconArt.wholeBlueSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: IconArt.displaySymbol(name), accessibilityDescription: nil), name)
        }
        // Layered symbols stay out of the whole-blue set.
        for name in ["square.and.arrow.up", "macwindow.badge.plus"] { XCTAssertFalse(IconArt.isWholeBlue(name), name) }
    }

    func testPaletteSymbolsHaveTwoColourLayers() throws {
        for dark in [false, true] {
            let layered = try colours(XCTUnwrap(IconArt.coloredNSImage("square.and.arrow.up", pointSize: 15, weight: .regular, dark: dark)))
            XCTAssertTrue(layered.contains(where: isBlue), "accent layer")
            XCTAssertTrue(layered.contains(where: isNeutral), "label layer")
            let whole = try colours(XCTUnwrap(IconArt.coloredNSImage("magnifyingglass", pointSize: 15, weight: .regular, dark: dark)))
            XCTAssertTrue(whole.contains(where: isBlue))
            XCTAssertFalse(whole.contains(where: isNeutral), "whole systemBlue has no label layer")
        }
    }

    func testIconsBelow14ptStaySingleColour() throws {
        for symbol in ["square.and.arrow.up", "text.magnifyingglass"] {
            let small = try render(IconArt.image(symbol, pointSize: 13).foregroundStyle(Color.red))
            XCTAssertFalse(small.contains(where: isBlue), "\(symbol) 13pt")
            let row = try render(IconArt.image(symbol, pointSize: 15).foregroundStyle(Color.red))
            XCTAssertTrue(row.contains(where: isBlue), "\(symbol) 15pt")
        }
        // Chips, pills and the notice are whole blue even when small.
        let chip = try render(IconArt.blueImage("square.and.arrow.up", pointSize: DesignTokens.fontCaption))
        XCTAssertTrue(chip.contains(where: isBlue))
        XCTAssertFalse(chip.contains(where: isNeutral))
    }

    func testSelectionKeepsColourOutsideTheToolbar() throws {
        XCTAssertEqual(IconArt.selectionFillOpacity, 0.12)
        XCTAssertEqual(IconArt.selectionStroke, 1)
        // Only the blue toolbar button turns art white; the normal art (cards, rows, picker) keeps the accent.
        let normal = try colours(XCTUnwrap(BIcons.image("arrow.uturn.backward.circle", side: 24, style: .normal, dark: false)))
        XCTAssertTrue(normal.contains(where: isBlue))
        let onAccent = try colours(XCTUnwrap(BIcons.image("arrow.uturn.backward.circle", side: 24, style: .onAccent, dark: false)))
        XCTAssertFalse(onAccent.contains(where: isBlue))
    }

    func testResetAndAutomationUseTheirArt() {
        XCTAssertEqual(BIcons.key(for: FloatingAction.restoreDisplay.symbol), "reset")
        XCTAssertEqual(FloatingAction.restoreDisplay.symbol, "arrow.uturn.backward.circle")
        XCTAssertEqual(BIcons.key(for: "gearshape.2"), "automation")
        for side in ToolbarSide.allCases { XCTAssertEqual(BIcons.key(for: side.collapseSymbol), "collapse", "\(side)") }
    }

    func testAttachedPanelBlurIsDenserThanTheToolbar() {
        XCTAssertEqual(DesignTokens.NS.attachedPanelLightBlurAlpha, 0.85)
        XCTAssertEqual(DesignTokens.NS.toolbarLightBlurAlpha, 0.70)
    }

    /// Every SF Symbol the app can draw must exist on macOS 14. Symbols that are only keys into B art
    /// (the collapse chevrons) are exempt because they are never drawn as SF Symbols.
    func testNoSymbolNewerThanMacOS14() throws {
        let plistURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let symbols = plist["symbols"] as? [String: String],
              let releases = plist["year_to_release"] as? [String: [String: String]] else { throw XCTSkip("name_availability.plist unavailable") }
        var names = Set(IconArt.wholeBlueSymbols).union(ShortcutIcon.allCases.map { IconArt.displaySymbol($0.rawValue) })
        names.formUnion(FloatingAction.allCases.map(\.symbol))
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RemoteFit")
        let pattern = try NSRegularExpression(pattern: #"(?:systemName|systemImage|symbol|systemSymbolName):\s*"([a-z0-9.]+)""#)
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { names.insert(String(text[range])) }
            }
        }
        let bOnly = Set(ToolbarSide.allCases.map(\.collapseSymbol))
        var newer: [String] = []
        for name in names.subtracting(bOnly) {
            guard let year = symbols[name], let mac = releases[year]?["macOS"] else { continue }
            if (Int(mac.split(separator: ".").first ?? "0") ?? 0) > 14 { newer.append("\(name) (\(mac))") }
        }
        XCTAssertEqual(newer.sorted(), [])
    }

    // MARK: - Pixels

    private func isBlue(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.b > c.r + 0.3 }
    private func isNeutral(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        abs(c.r - c.g) < 0.06 && abs(c.g - c.b) < 0.06
    }

    private func render<V: View>(_ view: V) throws -> [(r: CGFloat, g: CGFloat, b: CGFloat)] {
        let renderer = ImageRenderer(content: view.padding(2))
        renderer.scale = 2
        return try colours(XCTUnwrap(renderer.nsImage))
    }

    /// Un-premultiplied colours of the clearly covered pixels.
    private func colours(_ image: NSImage) throws -> [(r: CGFloat, g: CGFloat, b: CGFloat)] {
        let w = max(1, Int(image.size.width * 2)), h = max(1, Int(image.size.height * 2))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var out: [(r: CGFloat, g: CGFloat, b: CGFloat)] = []
        for x in 0..<w { for y in 0..<h {
            guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.8 else { continue }
            out.append((c.redComponent, c.greenComponent, c.blueComponent))
        } }
        return out
    }
}
