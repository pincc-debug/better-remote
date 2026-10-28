import AppKit
import SwiftUI

/// Icon style B (分层彩色, icon-style-compare/assets/svg-b): the icons-v1 outline shapes on a 24-unit grid with
/// 1.5-unit round strokes in the label colour, plus one semantic part per icon in a system accent colour
/// (stroke + a 20–28% fill of the same colour). Colours resolve per appearance; on the blue selection
/// everything turns white, and a selection inside a light card is blue line + blue 20% fill.
enum BIcons {
    enum Role { case fg, blue, orange, green }
    enum Style {
        /// Label-colour lines plus the accent part.
        case normal
        /// On the blue selection fill: every layer white, fills keep their 10–28% opacity.
        case onAccent
        /// Selected inside a light card: every line blue, every fill blue 20%.
        case selectedInCard
    }
    /// Immutable once built (paths are never mutated after `path(_:)` returns).
    enum Geo: @unchecked Sendable {
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, r: CGFloat)
        case circle(CGFloat, CGFloat, r: CGFloat)
        case custom(CGPath)
        var path: CGPath {
            switch self {
            case .rect(let x, let y, let w, let h, let r):
                CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
            case .circle(let x, let y, let r): CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
            case .custom(let path): path
            }
        }
    }
    struct BLayer: Sendable {
        let geo: Geo
        let stroke: Role?
        let strokeOpacity: CGFloat
        let width: CGFloat
        let fill: Role?
        let fillOpacity: CGFloat
        init(_ geo: Geo, stroke: Role?, strokeOpacity: CGFloat, width: CGFloat, fill: Role?, fillOpacity: CGFloat) {
            self.geo = geo; self.stroke = stroke; self.strokeOpacity = strokeOpacity; self.width = width
            self.fill = fill; self.fillOpacity = fillOpacity
        }
    }

    /// No layer fill may exceed this (spec: accent fills 20–28%).
    static let maxFillOpacity: CGFloat = 0.28
    /// Fill used by `.selectedInCard`.
    static let cardSelectionFillOpacity: CGFloat = 0.20
    /// Inline icons smaller than this stay single-colour outline (SF Symbols / template art).
    static let minimumPointSize: CGFloat = 14

    /// Stored icon / SF Symbol name → art key. Unlisted names keep their single-colour symbol.
    static let keys: [String: String] = [
        "text.magnifyingglass": "spotlight", "magnifyingglass": "spotlight",
        "doc.on.clipboard": "paste", "clipboard": "paste",
        "doc.on.doc": "copy",
        "arrow.left.arrow.right": "switch-app",
        "arrow.left": "desktop-left", "arrow.right": "desktop-right",
        "return": "return",
        "dock.rectangle": "dock",
        "arrow.up.left.and.arrow.down.right.square": "fill",
        "minus.rectangle": "minimize",
        "rectangle.on.rectangle.slash": "clear-desktop",
        "macwindow.on.rectangle": "mission-control",
        "square.grid.2x2": "apps",
        "rectangle.split.2x2": "window-layout",
        "display.2": "displays",
        "gearshape": "settings",
        "chevron.right.2": "collapse", "chevron.down.2": "collapse", "chevron.left.2": "collapse", "chevron.up.2": "collapse",
    ]

    static func key(for symbol: String) -> String? { keys[symbol] }

    /// The collapse art points right; the other docking sides turn it (quarter turns, clockwise on screen).
    static func quarterTurns(for symbol: String) -> Int {
        switch symbol {
        case "chevron.down.2": 1
        case "chevron.left.2": 2
        case "chevron.up.2": 3
        default: 0
        }
    }

    /// A square `side`×`side` image of the B art (the 24-unit grid scaled to `side`), or nil when `symbol` has none.
    /// Not a template: colours are baked for `dark`, so callers re-render on appearance and selection changes.
    static func image(_ symbol: String, side: CGFloat, style: Style, dark: Bool) -> NSImage? {
        guard let key = key(for: symbol), let layers = art[key] else { return nil }
        let turns = quarterTurns(for: symbol)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: rect.width / 24, y: rect.height / 24)
            if turns != 0 {
                context.translateBy(x: 12, y: 12)
                context.rotate(by: CGFloat(turns) * .pi / 2)
                context.translateBy(x: -12, y: -12)
            }
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let draw = {
                for layer in layers {
                    let path = layer.geo.path
                    if let fill = layer.fill {
                        let opacity = style == .selectedInCard ? cardSelectionFillOpacity : min(layer.fillOpacity, maxFillOpacity)
                        let base = color(fill, style).cgColor
                        context.addPath(path)
                        context.setFillColor(base.copy(alpha: base.alpha * opacity) ?? base)
                        context.fillPath()
                    }
                    if let stroke = layer.stroke {
                        let base = color(stroke, style).cgColor
                        context.addPath(path)
                        context.setStrokeColor(base.copy(alpha: base.alpha * layer.strokeOpacity) ?? base)
                        context.setLineWidth(layer.width)
                        context.strokePath()
                    }
                }
            }
            if let appearance { appearance.performAsCurrentDrawingAppearance(draw) } else { draw() }
            context.restoreGState()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = nil
        return image
    }

    static func color(_ role: Role, _ style: Style) -> NSColor {
        switch style {
        case .onAccent: return .white
        case .selectedInCard: return .systemBlue
        case .normal:
            switch role {
            case .fg: return DesignTokens.NS.textPrimary
            case .blue: return .systemBlue
            case .orange: return .systemOrange
            case .green: return .systemGreen
            }
        }
    }

    private static func path(_ build: (CGMutablePath) -> Void) -> Geo {
        let path = CGMutablePath()
        build(path)
        return .custom(path)
    }

    // Generated from icon-style-compare/b_icons.py (arcs and quadratics converted to cubics); do not hand-edit shapes.
    static let art: [String: [BLayer]] = [
        "spotlight": [
            BLayer(.circle(10.5, 10.5, r: 6.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(path { p in p.move(to: P(15.4, 15.4)); p.addLine(to: P(20.25, 20.25)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "paste": [
            BLayer(.rect(5, 4.75, 14, 16.5, r: 2.25), stroke: nil, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.2),
            BLayer(path { p in p.move(to: P(8.75, 4.75)); p.addLine(to: P(7.25, 4.75)); p.addCurve(to: P(5, 7), control1: P(6.0074, 4.75), control2: P(5, 5.7574)); p.addLine(to: P(5, 19)); p.addCurve(to: P(7.25, 21.25), control1: P(5, 20.2426), control2: P(6.0074, 21.25)); p.addLine(to: P(16.75, 21.25)); p.addCurve(to: P(19, 19), control1: P(17.9926, 21.25), control2: P(19, 20.2426)); p.addLine(to: P(19, 7)); p.addCurve(to: P(16.75, 4.75), control1: P(19, 5.7574), control2: P(17.9926, 4.75)); p.addLine(to: P(15.25, 4.75)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(.rect(8.75, 2.75, 6.5, 3.5, r: 1.25), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(9, 11.5)); p.addLine(to: P(15, 11.5)); p.move(to: P(9, 15.5)); p.addLine(to: P(13, 15.5)) }, stroke: .blue, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "copy": [
            BLayer(path { p in p.move(to: P(15.25, 8.75)); p.addLine(to: P(15.25, 6)); p.addCurve(to: P(13, 3.75), control1: P(15.25, 4.7574), control2: P(14.2426, 3.75)); p.addLine(to: P(6, 3.75)); p.addCurve(to: P(3.75, 6), control1: P(4.7574, 3.75), control2: P(3.75, 4.7574)); p.addLine(to: P(3.75, 13)); p.addCurve(to: P(6, 15.25), control1: P(3.75, 14.2426), control2: P(4.7574, 15.25)); p.addLine(to: P(8.75, 15.25)) }, stroke: .fg, strokeOpacity: 0.5, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(.rect(8.75, 8.75, 11.5, 11.5, r: 2.25), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22)],
        "switch-app": [
            BLayer(path { p in p.move(to: P(4, 8)); p.addLine(to: P(19.5, 8)); p.move(to: P(16, 4.5)); p.addLine(to: P(19.5, 8)); p.addLine(to: P(16, 11.5)) }, stroke: .blue, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(20, 16)); p.addLine(to: P(4.5, 16)); p.move(to: P(8, 12.5)); p.addLine(to: P(4.5, 16)); p.addLine(to: P(8, 19.5)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "desktop-left": [
            BLayer(path { p in p.move(to: P(19.75, 12)); p.addLine(to: P(4.5, 12)) }, stroke: .fg, strokeOpacity: 0.45, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(10.5, 6)); p.addLine(to: P(4.5, 12)); p.addLine(to: P(10.5, 18)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "desktop-right": [
            BLayer(path { p in p.move(to: P(4.25, 12)); p.addLine(to: P(19.5, 12)) }, stroke: .fg, strokeOpacity: 0.45, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(13.5, 6)); p.addLine(to: P(19.5, 12)); p.addLine(to: P(13.5, 18)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "return": [
            BLayer(path { p in p.move(to: P(19.25, 4.75)); p.addLine(to: P(19.25, 11)); p.addCurve(to: P(16, 14.25), control1: P(19.25, 12.7949), control2: P(17.7949, 14.25)); p.addLine(to: P(5, 14.25)) }, stroke: .fg, strokeOpacity: 0.45, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(9, 10.25)); p.addLine(to: P(5, 14.25)); p.addLine(to: P(9, 18.25)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "dock": [
            BLayer(.rect(2.75, 4.25, 18.5, 15.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: .fg, fillOpacity: 0.12),
            BLayer(path { p in p.move(to: P(7.5, 16.25)); p.addLine(to: P(16.5, 16.25)) }, stroke: .blue, strokeOpacity: 1, width: 2, fill: nil, fillOpacity: 1)],
        "fill": [
            BLayer(.rect(3.75, 3.75, 16.5, 16.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.2),
            BLayer(path { p in p.move(to: P(8, 11.5)); p.addLine(to: P(8, 8)); p.addLine(to: P(11.5, 8)); p.move(to: P(16, 12.5)); p.addLine(to: P(16, 16)); p.addLine(to: P(12.5, 16)); p.move(to: P(8.25, 8.25)); p.addLine(to: P(15.75, 15.75)) }, stroke: .blue, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "minimize": [
            BLayer(.rect(3.75, 3.75, 16.5, 16.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: .fg, fillOpacity: 0.12),
            BLayer(path { p in p.move(to: P(8.5, 12)); p.addLine(to: P(15.5, 12)) }, stroke: .orange, strokeOpacity: 1, width: 2, fill: nil, fillOpacity: 1)],
        "clear-desktop": [
            BLayer(.rect(2.75, 4.25, 18.5, 15.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: .fg, fillOpacity: 0.1),
            BLayer(path { p in p.move(to: P(12, 7.75)); p.addCurve(to: P(16.25, 12), control1: P(12.3667, 10.2167), control2: P(13.7833, 11.6333)); p.addCurve(to: P(12, 16.25), control1: P(13.7833, 12.3667), control2: P(12.3667, 13.7833)); p.addCurve(to: P(7.75, 12), control1: P(11.6333, 13.7833), control2: P(10.2167, 12.3667)); p.addCurve(to: P(12, 7.75), control1: P(10.2167, 11.6333), control2: P(11.6333, 10.2167)); p.closeSubpath() }, stroke: .green, strokeOpacity: 1, width: 1.5, fill: .green, fillOpacity: 0.25)],
        "mission-control": [
            BLayer(path { p in p.move(to: P(5.25, 4.25)); p.addLine(to: P(18.75, 4.25)); p.addCurve(to: P(21.25, 6.75), control1: P(20.1307, 4.25), control2: P(21.25, 5.3693)); p.addLine(to: P(21.25, 8.75)); p.addLine(to: P(2.75, 8.75)); p.addLine(to: P(2.75, 6.75)); p.addCurve(to: P(5.25, 4.25), control1: P(2.75, 5.3693), control2: P(3.8693, 4.25)); p.closeSubpath() }, stroke: nil, strokeOpacity: 1, width: 1.5, fill: .fg, fillOpacity: 0.18),
            BLayer(.rect(2.75, 4.25, 18.5, 15.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(2.75, 8.75)); p.addLine(to: P(21.25, 8.75)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(.rect(6.25, 11.75, 4.75, 4.5, r: 1), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(.rect(13, 11.75, 4.75, 4.5, r: 1), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22)],
        "apps": [
            BLayer(.rect(3.75, 3.75, 6.75, 6.75, r: 1.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(.rect(13.5, 3.75, 6.75, 6.75, r: 1.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(.rect(3.75, 13.5, 6.75, 6.75, r: 1.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(.rect(13.5, 13.5, 6.75, 6.75, r: 1.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22)],
        "window-layout": [
            BLayer(path { p in p.move(to: P(6.25, 3.75)); p.addLine(to: P(12, 3.75)); p.addLine(to: P(12, 12)); p.addLine(to: P(3.75, 12)); p.addLine(to: P(3.75, 6.25)); p.addCurve(to: P(6.25, 3.75), control1: P(3.75, 4.8693), control2: P(4.8693, 3.75)); p.closeSubpath() }, stroke: nil, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.28),
            BLayer(.rect(3.75, 3.75, 16.5, 16.5, r: 2.5), stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(12, 3.75)); p.addLine(to: P(12, 20.25)); p.move(to: P(3.75, 12)); p.addLine(to: P(20.25, 12)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "displays": [
            BLayer(path { p in p.move(to: P(9, 8)); p.addLine(to: P(9, 5.25)); p.addCurve(to: P(10.5, 3.75), control1: P(9, 4.4216), control2: P(9.6716, 3.75)); p.addLine(to: P(19.5, 3.75)); p.addCurve(to: P(21, 5.25), control1: P(20.3284, 3.75), control2: P(21, 4.4216)); p.addLine(to: P(21, 10.5)); p.addCurve(to: P(19.5, 12), control1: P(21, 11.3284), control2: P(20.3284, 12)); p.addLine(to: P(15, 12)) }, stroke: .fg, strokeOpacity: 0.5, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(.rect(3, 8, 12, 8.75, r: 1.5), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.22),
            BLayer(path { p in p.move(to: P(9, 16.75)); p.addLine(to: P(9, 19.75)); p.move(to: P(6.5, 20)); p.addLine(to: P(11.5, 20)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
        "settings": [
            BLayer(path { p in p.move(to: P(9.733, 5.377)); p.addLine(to: P(9.899, 3.249)); p.addCurve(to: P(14.101, 3.249), control1: P(11.28, 2.9174), control2: P(12.72, 2.9174)); p.addLine(to: P(14.267, 5.377)); p.addCurve(to: P(15.08, 5.714), control1: P(14.5448, 5.4722), control2: P(14.8163, 5.5847)); p.addLine(to: P(16.702, 4.326)); p.addCurve(to: P(19.674, 7.298), control1: P(17.9133, 5.0682), control2: P(18.9318, 6.0867)); p.addLine(to: P(18.286, 8.92)); p.addCurve(to: P(18.623, 9.733), control1: P(18.4153, 9.1837), control2: P(18.5278, 9.4552)); p.addLine(to: P(20.751, 9.899)); p.addCurve(to: P(20.751, 14.101), control1: P(21.0826, 11.28), control2: P(21.0826, 12.72)); p.addLine(to: P(18.623, 14.267)); p.addCurve(to: P(18.286, 15.08), control1: P(18.5278, 14.5448), control2: P(18.4153, 14.8163)); p.addLine(to: P(19.674, 16.702)); p.addCurve(to: P(16.702, 19.674), control1: P(18.9318, 17.9133), control2: P(17.9133, 18.9318)); p.addLine(to: P(15.08, 18.286)); p.addCurve(to: P(14.267, 18.623), control1: P(14.8163, 18.4153), control2: P(14.5448, 18.5278)); p.addLine(to: P(14.101, 20.751)); p.addCurve(to: P(9.899, 20.751), control1: P(12.72, 21.0826), control2: P(11.28, 21.0826)); p.addLine(to: P(9.733, 18.623)); p.addCurve(to: P(8.92, 18.286), control1: P(9.4552, 18.5278), control2: P(9.1837, 18.4153)); p.addLine(to: P(7.298, 19.674)); p.addCurve(to: P(4.326, 16.702), control1: P(6.0867, 18.9318), control2: P(5.0682, 17.9133)); p.addLine(to: P(5.714, 15.08)); p.addCurve(to: P(5.377, 14.267), control1: P(5.5847, 14.8163), control2: P(5.4722, 14.5448)); p.addLine(to: P(3.249, 14.101)); p.addCurve(to: P(3.249, 9.899), control1: P(2.9174, 12.72), control2: P(2.9174, 11.28)); p.addLine(to: P(5.377, 9.733)); p.addCurve(to: P(5.714, 8.92), control1: P(5.4722, 9.4552), control2: P(5.5847, 9.1837)); p.addLine(to: P(4.326, 7.298)); p.addCurve(to: P(7.298, 4.326), control1: P(5.0682, 6.0867), control2: P(6.0867, 5.0682)); p.addLine(to: P(8.92, 5.714)); p.addCurve(to: P(9.733, 5.377), control1: P(9.1837, 5.5847), control2: P(9.4552, 5.4722)); p.closeSubpath() }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: .fg, fillOpacity: 0.14),
            BLayer(.circle(12, 12, r: 2.75), stroke: .blue, strokeOpacity: 1, width: 1.5, fill: .blue, fillOpacity: 0.25)],
        "collapse": [
            BLayer(path { p in p.move(to: P(6, 6)); p.addLine(to: P(12, 12)); p.addLine(to: P(6, 18)) }, stroke: .fg, strokeOpacity: 0.45, width: 1.5, fill: nil, fillOpacity: 1),
            BLayer(path { p in p.move(to: P(12.5, 6)); p.addLine(to: P(18.5, 12)); p.addLine(to: P(12.5, 18)) }, stroke: .fg, strokeOpacity: 1, width: 1.5, fill: nil, fillOpacity: 1)],
    ]
}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// SwiftUI host for B art: re-renders for the current colour scheme.
struct BIconImage: View {
    let symbol: String
    let side: CGFloat
    var style: BIcons.Style = .normal
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        if let image = BIcons.image(symbol, side: side, style: style, dark: colorScheme == .dark) {
            Image(nsImage: image).accessibilityHidden(true)
        }
    }
}
