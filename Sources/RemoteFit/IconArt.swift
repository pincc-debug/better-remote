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

    /// SwiftUI icon; `pointSize` is the font size the call site already uses. Toolbar actions with style-B art
    /// draw it (same art and colours as the toolbar) from 14pt up; smaller inline icons stay single-colour.
    /// `selectedInCard`: selected inside a light card (blue line + blue 20% fill).
    @ViewBuilder
    static func image(_ name: String, pointSize: CGFloat, weight: Font.Weight = .regular, selectedInCard: Bool = false) -> some View {
        if pointSize >= BIcons.minimumPointSize, BIcons.key(for: name) != nil {
            BIconImage(symbol: name, side: (pointSize * bArtScale).rounded(), style: selectedInCard ? .selectedInCard : .normal)
        } else {
            symbolImage(name, pointSize: pointSize, weight: weight)
        }
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

    // MARK: - Sidebar 连接自动化 (icons-v1/sb-automation.svg)

    private enum Segment {
        case move(CGFloat, CGFloat), line(CGFloat, CGFloat), arc(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat), close
    }
    private static let gears: [[Segment]] = [
        [.move(9.422,4.199), .line(10.364,2.971), .arc(8.75,8.75,6.0,-74.396,-45.601), .line(12.355,5.893), .arc(8.75,8.75,4.6,-38.397,-21.596), .line(14.561,7.258), .arc(8.75,8.75,6.0,-14.400,14.400), .line(13.027,10.443), .arc(8.75,8.75,4.6,21.596,38.397), .line(12.948,13.037), .arc(8.75,8.75,6.0,45.601,74.396), .line(9.422,13.301), .arc(8.75,8.75,4.6,81.600,98.400), .line(7.136,14.529), .arc(8.75,8.75,6.0,105.604,134.399), .line(5.145,11.607), .arc(8.75,8.75,4.6,141.603,158.404), .line(2.939,10.242), .arc(8.75,8.75,6.0,165.600,194.400), .line(4.473,7.057), .arc(8.75,8.75,4.6,-158.404,-141.603), .line(4.552,4.463), .arc(8.75,8.75,6.0,-134.399,-105.604), .line(8.078,4.199), .arc(8.75,8.75,4.6,-98.400,-81.600), .close],
        [.move(15.667,13.785), .line(15.85,12.422), .arc(16.9,16.9,4.6,-103.196,-76.804), .line(18.133,13.785), .arc(16.9,16.9,3.35,-68.405,-51.594), .line(20.253,13.751), .arc(16.9,16.9,4.6,-43.203,-16.804), .line(20.214,16.411), .arc(16.9,16.9,3.35,-8.394,8.394), .line(21.304,18.23), .arc(16.9,16.9,4.6,16.804,43.203), .line(18.981,19.525), .arc(16.9,16.9,3.35,51.594,68.405), .line(17.95,21.378), .arc(16.9,16.9,4.6,76.804,103.196), .line(15.667,20.015), .arc(16.9,16.9,3.35,111.595,128.406), .line(13.547,20.049), .arc(16.9,16.9,4.6,136.797,163.196), .line(13.586,17.389), .arc(16.9,16.9,3.35,171.606,188.394), .line(12.496,15.57), .arc(16.9,16.9,4.6,-163.196,-136.797), .line(14.819,14.275), .arc(16.9,16.9,3.35,-128.406,-111.595), .close],
    ]

    /// Two-gear template drawn on the 24 grid; `side` is the drawn square in points.
    static func automationImage(side: CGFloat, semibold: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            let scale = rect.width / 24
            var paths: [NSBezierPath] = []
            for gear in gears {
                let path = NSBezierPath()
                for segment in gear {
                    switch segment {
                    case .move(let x, let y): path.move(to: NSPoint(x: x, y: y))
                    case .line(let x, let y): path.line(to: NSPoint(x: x, y: y))
                    case .arc(let cx, let cy, let r, let from, let to):
                        // y-down artboard: increasing angle is visually clockwise (SVG sweep 1).
                        path.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: from, endAngle: to, clockwise: false)
                    case .close: path.close()
                    }
                }
                paths.append(path)
            }
            paths.append(NSBezierPath(ovalIn: NSRect(x: 8.75 - 1.8, y: 8.75 - 1.8, width: 3.6, height: 3.6)))
            paths.append(NSBezierPath(ovalIn: NSRect(x: 16.9 - 1.1, y: 16.9 - 1.1, width: 2.2, height: 2.2)))
            let transform = AffineTransform(scale: scale)
            for path in paths {
                path.transform(using: transform)
                path.lineWidth = (semibold ? 1.75 : 1.5) * scale
                path.lineCapStyle = .round; path.lineJoinStyle = .round
                NSColor.black.setStroke(); path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
