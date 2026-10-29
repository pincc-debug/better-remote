import AppKit
import SwiftUI

/// Display-only icon art. Stored icon names (ShortcutIcon raw values, preferences) never change;
/// a few are drawn with a lighter outline variant or a custom template at render time.
enum IconArt {
    /// SF Symbol names stored in preferences mapped to the outline variant shown on screen.
    private static let outline: [String: String] = [
        "doc.on.clipboard": "clipboard",
        "rectangle.split.2x1.fill": "rectangle.split.2x1",
        "rectangle.split.1x2.fill": "rectangle.split.1x2",
        "plus.square.fill": "plus.square",
    ]
    /// Drawn from icons-v1/copy.svg instead of the SF Symbol.
    static let customCopy = "doc.on.doc"

    static func displaySymbol(_ name: String) -> String { outline[name] ?? name }

    /// Template image for the toolbar (AppKit). Same box as the SF Symbol at that size.
    static func nsImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        if name == customCopy {
            let size = NSImage(systemSymbolName: customCopy, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)?.size ?? NSSize(width: pointSize * 1.3, height: pointSize * 1.43)
            return copyImage(size: size, weight: weight)
        }
        return NSImage(systemSymbolName: displaySymbol(name), accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    // MARK: - Colour (icon-color-rules.md)

    /// Symbols drawn whole systemBlue instead of palette(label, systemBlue): no second palette layer on macOS
    /// (palette self-check, 136 red-only), plus five whose second layer reads wrong as blue
    /// (arrow.up.arrow.down: 反转滚动方向, 像素之眼 wants it one accent blue like 单指滚动).
    static let wholeBlueSymbols: Set<String> = [
        "airplane", "app", "arrow.clockwise", "arrow.counterclockwise", "arrow.down", "arrow.down.right.and.arrow.up.left",
        "arrow.down.to.line", "arrow.left", "arrow.right", "arrow.right.to.line", "arrow.triangle.2.circlepath", "arrow.up",
        "arrow.up.and.down.and.arrow.left.and.right", "arrow.up.left.and.arrow.down.right", "arrow.up.to.line", "arrow.uturn.backward",
        "arrow.uturn.forward", "aspectratio", "at", "backward.fill", "bell.fill", "bold", "bolt", "bookmark.fill", "bubble.left",
        "calendar", "camera", "car.fill", "cart.fill", "chart.bar.fill", "checkmark", "chevron.down", "chevron.down.2", "chevron.left",
        "chevron.left.2", "chevron.left.forwardslash.chevron.right", "chevron.right", "chevron.right.2", "chevron.up", "chevron.up.2",
        "chevron.up.chevron.down", "circle.grid.3x3.fill", "circle.lefthalf.filled", "clipboard", "clock.fill", "cloud.fill", "command",
        "cpu", "creditcard.fill", "cup.and.saucer", "curlybraces", "cursorarrow", "doc.fill", "drop.fill", "ellipsis", "envelope.fill",
        "eye.fill", "figure.walk", "flag.fill", "flame.fill", "flashlight.on.fill", "folder.fill", "forward.fill", "gamecontroller.fill",
        "gearshape", "gearshape.2", "gift.fill", "globe", "hammer.fill", "hand.raised.fill", "hand.thumbsup.fill", "headphones",
        "heart.fill", "house.fill", "italic", "key.fill", "keyboard", "leaf.fill", "line.3.horizontal", "link", "location.fill",
        "lock.fill", "lock.open.fill", "magnifyingglass", "map.fill", "message.fill", "mic", "minus", "moon.fill", "music.note", "number",
        "option", "paintbrush.fill", "paperclip", "pause.fill", "pencil", "person.fill", "phone.fill", "photo.fill", "pin.fill",
        "play.fill", "plus", "plus.forwardslash.minus", "power", "printer.fill", "rectangle.split.1x2", "rectangle.split.1x2.fill",
        "rectangle.split.2x1", "rectangle.split.2x1.fill", "rectangle.split.2x2", "rectangle.split.2x2.fill", "rectangle.split.3x1.fill",
        "rectangle.stack.fill", "return", "scissors", "sidebar.left", "sidebar.right", "slider.horizontal.3", "sparkles", "square.dashed",
        "square.grid.2x2", "star", "star.fill", "stop.fill", "sun.max.fill", "sun.min.fill", "tag", "tag.fill", "terminal.fill",
        "textformat", "trash", "trash.fill", "video.fill", "viewfinder", "wifi", "xmark",
        "hand.draw", "hand.tap.fill", "lightbulb.fill", "speaker.wave.1.fill", "arrow.up.arrow.down",
    ]
    static func isWholeBlue(_ name: String) -> Bool {
        wholeBlueSymbols.contains(name) || wholeBlueSymbols.contains(displaySymbol(name))
    }
    /// Selected cell / card / row: accent 12% background plus a 1pt accent stroke; the icon keeps its colours.
    static let selectionFillOpacity: CGFloat = 0.12
    static let selectionStroke: CGFloat = 1
    /// First palette layer (same label colour as the B art lines) and the accent layer.
    static let labelColor = Color(nsColor: DesignTokens.NS.textPrimary)
    static let blue = Color(nsColor: .systemBlue)

    /// SwiftUI icon; `pointSize` is the font size the call site already uses. From 14pt up the icon is coloured
    /// (B art when the action has it, else the SF Symbol as palette label + systemBlue, or whole systemBlue);
    /// smaller inline icons stay single-colour and honour the caller's foreground style.
    /// A selected icon in a card, row or picker keeps its colours: selection is the background and stroke.
    @ViewBuilder
    static func image(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular) -> some View {
        if pointSize >= BIcons.minimumPointSize {
            coloredImage(name, pointSize: pointSize, weight: weight)
        } else {
            symbolImage(name, pointSize: pointSize, weight: weight)
        }
    }

    /// Always coloured, whatever the size (callers below 14pt use `image` or `blueImage` instead).
    @ViewBuilder
    static func coloredImage(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular) -> some View {
        if BIcons.key(for: name) != nil {
            BIconImage(symbol: name, side: (pointSize * bArtScale).rounded(), style: .normal)
        } else if isWholeBlue(name) {
            symbolImage(name, pointSize: pointSize, weight: weight)
                .font(.system(size: pointSize, weight: weight)).foregroundStyle(blue)
        } else {
            symbolImage(name, pointSize: pointSize, weight: weight)
                .symbolRenderingMode(.palette)
                .font(.system(size: pointSize, weight: weight)).foregroundStyle(labelColor, blue)
        }
    }

    /// Whole systemBlue single-colour icon (app chips, about pills, the notice bar).
    static func blueImage(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular) -> some View {
        symbolImage(name, pointSize: pointSize, weight: weight)
            .font(.system(size: pointSize, weight: weight)).foregroundStyle(blue)
    }

    /// The one close glyph for sheets, pickers and cards: 13pt medium `xmark` on a 28×28 secondaryFill circle.
    static func closeGlyph() -> some View {
        Image(systemName: "xmark")
            .font(.system(size: DesignTokens.fontBody, weight: .medium))
            .frame(width: closeDiameter, height: closeDiameter)
            .background(DesignTokens.Colors.secondaryFill, in: Circle())
            .contentShape(Circle())
    }
    static let closeDiameter: CGFloat = 28

    /// AppKit counterpart of `coloredImage` for an SF Symbol without B art (toolbar actions). Colours are baked for
    /// `dark` (not a template); nil when the symbol does not exist.
    static func coloredNSImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, dark: Bool) -> NSImage? {
        guard name != customCopy else { return nil }
        var palette: [NSColor] = []
        let resolve = {
            let colors: [NSColor] = isWholeBlue(name) ? [.systemBlue] : [DesignTokens.NS.textPrimary, .systemBlue]
            palette = colors.map { NSColor(cgColor: $0.cgColor) ?? $0 }
        }
        if let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) { appearance.performAsCurrentDrawingAppearance(resolve) } else { resolve() }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: palette))
        guard let image = NSImage(systemSymbolName: displaySymbol(name), accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        image.isTemplate = false
        return image
    }

    /// B art fills its 24-unit grid; this keeps it at about the footprint of the symbol it replaces in rows.
    static let bArtScale: CGFloat = 1.2

    /// Single-colour image (template), honouring the caller's foreground style.
    static func symbolImage(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular) -> Image {
        if name == customCopy, let image = nsImage(name, pointSize: pointSize, weight: nsWeight(weight)) {
            return Image(nsImage: image).renderingMode(.template)
        }
        return Image(systemName: displaySymbol(name))
    }

    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .semibold: .semibold
        case .bold, .heavy, .black: .bold
        case .medium: .medium
        case .light, .thin, .ultraLight: .light
        default: .regular
        }
    }

    /// Stroke width in 24-unit artboard units, roughly following SF Symbol weights.
    private static func strokeUnits(_ weight: NSFont.Weight) -> CGFloat {
        if weight >= .bold { return 1.65 }
        if weight >= .semibold { return 1.5 }
        if weight >= .medium { return 1.35 }
        return 1.2
    }

    private static func copyImage(size: NSSize, weight: NSFont.Weight) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            // copy.svg content spans 3..21 on the 24 grid (with stroke); fit it to the symbol box.
            let scale = min(rect.width, rect.height) / 19.5
            let transform = AffineTransform(m11: scale, m12: 0, m21: 0, m22: scale,
                                            tX: rect.midX - 12 * scale, tY: rect.midY - 12 * scale)
            let front = NSBezierPath(roundedRect: NSRect(x: 8.75, y: 8.75, width: 11.5, height: 11.5), xRadius: 2.25, yRadius: 2.25)
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 15.25, y: 8.75))
            back.line(to: NSPoint(x: 15.25, y: 6))
            back.appendArc(withCenter: NSPoint(x: 13, y: 6), radius: 2.25, startAngle: 0, endAngle: -90, clockwise: true)
            back.line(to: NSPoint(x: 6, y: 3.75))
            back.appendArc(withCenter: NSPoint(x: 6, y: 6), radius: 2.25, startAngle: -90, endAngle: -180, clockwise: true)
            back.line(to: NSPoint(x: 3.75, y: 13))
            back.appendArc(withCenter: NSPoint(x: 6, y: 13), radius: 2.25, startAngle: 180, endAngle: 90, clockwise: true)
            back.line(to: NSPoint(x: 8.75, y: 15.25))
            for path in [front, back] {
                path.transform(using: transform)
                path.lineWidth = strokeUnits(weight) * scale
                path.lineCapStyle = .round; path.lineJoinStyle = .round
                NSColor.black.setStroke(); path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
