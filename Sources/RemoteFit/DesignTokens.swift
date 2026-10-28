import AppKit
import SwiftUI

/// Unified Design Tokens for RemoteFit (Oil UI 01 Precision Order)
/// Establishes 8pt spacing rhythm, semantic radii, and coherent specular materials.
public enum DesignTokens {
    // MARK: - Corner Radii
    // Three steps only (DESIGN.md 视觉档位): 6 small controls / icon bases,
    // 10 cards / fields / buttons, 14 panels / sheets, plus capsule.
    public static let radiusSm: CGFloat = 6
    public static let radiusMd: CGFloat = 10
    public static let radiusLg: CGFloat = 14
    /// Floating glass panels use the panel step.
    public static let radiusXl: CGFloat = radiusLg
    public static let radiusPill: CGFloat = 999

    // MARK: - Type scale
    public static let fontCaption: CGFloat = 11
    public static let fontBody: CGFloat = 13
    public static let fontEmphasis: CGFloat = 15
    public static let fontTitle: CGFloat = 20

    // MARK: - Stroke
    public static let selectedStroke: CGFloat = 2
    public static let glyphStroke: CGFloat = 1.5
    /// One physical pixel at the given backing scale (hairline edges).
    public static func hairline(scale: CGFloat) -> CGFloat { 1 / max(1, scale) }

    // MARK: - Controls
    /// Standard height of buttons, fields and dropdown rows.
    public static let controlHeight: CGFloat = 28
    /// Dropdown menus show at most this many rows before scrolling.
    public static let dropdownMaxRows = 8
    /// Minimum width of a settings dropdown trigger.
    public static let dropdownMinWidth: CGFloat = 160

    // MARK: - Floating toolbar shadow (drawn by the layer, not the window server)
    public static let toolbarShadowOpacity: Float = 0.22
    public static let toolbarShadowRadius: CGFloat = 14
    public static let toolbarShadowOffsetY: CGFloat = -2
    /// Glass dropdown keeps the earlier, tighter shadow.
    public static let dropdownShadowOpacity: Float = 0.18
    public static let dropdownShadowRadius: CGFloat = 4
    /// Blur of `NS.legibilityShadow` under toolbar glyphs and captions.
    public static let legibilityShadowRadius: CGFloat = 1.5

    // MARK: - Spacing & Metrics (8pt System)
    public static let spacingXs: CGFloat = 4
    public static let spacingSm: CGFloat = 8
    public static let spacingMd: CGFloat = 12
    public static let spacingLg: CGFloat = 16
    public static let spacingXl: CGFloat = 20

    // MARK: - NSColors (AppKit)
    public enum NS {
        /// Tint inside glass panels (toolbar, attached panels, flyouts, notices, dropdowns). Kept light so the
        /// glass reads as glass: white 6% (light) / black 14% (dark). Was 18% / 36% before 0.8.139.
        public static let glassBackdrop = adaptive("glassBackdrop", light: NSColor(calibratedWhite: 1, alpha: 0.06), dark: NSColor(calibratedWhite: 0, alpha: 0.14))
        /// Soft halo behind toolbar glyphs and captions so they stay legible over busy backgrounds.
        public static let legibilityShadow = adaptive("legibilityShadow", light: NSColor(calibratedWhite: 1, alpha: 0.7), dark: NSColor(calibratedWhite: 0, alpha: 0.5))
        public static let surface = adaptive("surface", light: NSColor(calibratedWhite: 1, alpha: 0.88), dark: NSColor(calibratedRed: 22/255, green: 23/255, blue: 27/255, alpha: 0.88))
        public static let surfaceElevated = adaptive("surfaceElevated", light: NSColor(calibratedWhite: 0.96, alpha: 0.94), dark: NSColor(calibratedRed: 32/255, green: 34/255, blue: 40/255, alpha: 0.94))
        public static let pedestalBg = adaptive("pedestalBg", light: NSColor(calibratedWhite: 0, alpha: 0.28), dark: NSColor(calibratedWhite: 1, alpha: 0.28))
        public static let pedestalBorder = adaptive("pedestalBorder", light: NSColor(calibratedWhite: 0, alpha: 0.08), dark: NSColor(calibratedWhite: 1, alpha: 0.08))
        /// Light mode only: opacity of the blur layer behind the toolbar and its joined resolution / app panels
        /// (`.sidebar` on macOS 26, `.popover` on 14–25), so more of the desktop shows through. Dark is unchanged.
        public static let toolbarLightBlurAlpha: CGFloat = 0.70
        /// Light-mode hairline alpha (black) for the toolbar and every panel attached to it (joined resolution /
        /// app panels, window-layout and app-shortcut flyouts). Dark stays white 15%. Was 9% before build 195.
        public static let toolbarLightHairlineAlpha: CGFloat = 0.12
        /// 1 px edge of the toolbar and its attached panels; none on the docked side or a join.
        public static let toolbarSurfaceHairline = adaptive("toolbarSurfaceHairline", light: NSColor(calibratedWhite: 0, alpha: toolbarLightHairlineAlpha), dark: NSColor(calibratedWhite: 1, alpha: 0.15))
        /// Tint inside the toolbar and its joined panels: none in light (the faded blur carries the surface), black 14% in dark.
        public static let toolbarSurfaceBackdrop = adaptive("toolbarSurfaceBackdrop", light: .clear, dark: NSColor(calibratedWhite: 0, alpha: 0.14))

        public static let buttonNormal = adaptive("buttonNormal", light: NSColor(calibratedWhite: 0, alpha: 0.025), dark: NSColor(calibratedWhite: 1, alpha: 0.025))
        public static let buttonNormalBorder = adaptive("buttonNormalBorder", light: NSColor(calibratedWhite: 0, alpha: 0.025), dark: NSColor(calibratedWhite: 1, alpha: 0.025))
        public static let buttonHighlight = adaptive("buttonHighlight", light: NSColor(calibratedWhite: 0, alpha: 0.16), dark: NSColor(calibratedWhite: 1, alpha: 0.16))
        public static let buttonActive = NSColor(calibratedRed: 0/255, green: 113/255, blue: 227/255, alpha: 0.92)
        public static let buttonActiveBorder = NSColor(calibratedWhite: 1, alpha: 0.32)

        public static let textPrimary = NSColor.labelColor
        public static let textSecondary = adaptive("textSecondary", light: NSColor(calibratedWhite: 0, alpha: 0.85), dark: NSColor(calibratedWhite: 1, alpha: 0.90))
        public static let textTertiary = NSColor.tertiaryLabelColor
    }

    fileprivate static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("BetterRemote.\(name)")) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Colors (SwiftUI)
    public enum Colors {
        public static let surface = Color(nsColor: NS.surface)
        public static let surfaceElevated = Color(nsColor: NS.surfaceElevated)
        public static let cardBg = Color.primary.opacity(0.065)
        public static let cardBgHover = Color.primary.opacity(0.12)
        public static let cardBorder = Color.primary.opacity(0.08)
        public static let cardBorderHighlight = Color.primary.opacity(0.16)

        public static let accent = Color(calibratedRed: 0/255, green: 113/255, blue: 227/255)
        public static let accentSubtle = Color(calibratedRed: 0/255, green: 113/255, blue: 227/255).opacity(0.24)
        public static let accentBorder = Color(calibratedRed: 56/255, green: 189/255, blue: 248/255)

        /// Brand blue 12%: selected toggle / chip fill.
        public static let accentFill = accent.opacity(0.12)
        /// Card on a panel or page background: white (light) / card grey (dark), no stroke.
        public static let card = Color(nsColor: adaptive("card", light: .white, dark: NSColor(calibratedWhite: 1, alpha: 0.07)))
        /// Card edge: primary 8% in light (white card on a light page), none in dark.
        public static let cardEdge = Color(nsColor: adaptive("cardEdge", light: NSColor(calibratedWhite: 0, alpha: 0.08), dark: .clear))
        /// Secondary button / unselected control fill: black 4% (light) / white 6% (dark).
        public static let secondaryFill = Color(nsColor: adaptive("secondaryFill", light: NSColor(calibratedWhite: 0, alpha: 0.04), dark: NSColor(calibratedWhite: 1, alpha: 0.06)))
        public static let secondaryFillPressed = Color(nsColor: adaptive("secondaryFillPressed", light: NSColor(calibratedWhite: 0, alpha: 0.09), dark: NSColor(calibratedWhite: 1, alpha: 0.12)))
        /// Segmented control track and thumb.
        public static let segmentTrack = Color(nsColor: adaptive("segmentTrack", light: NSColor(calibratedWhite: 0, alpha: 0.06), dark: NSColor(calibratedWhite: 1, alpha: 0.08)))
        public static let segmentThumb = Color(nsColor: adaptive("segmentThumb", light: .white, dark: NSColor(calibratedRed: 0x63/255, green: 0x63/255, blue: 0x66/255, alpha: 1)))
        /// Settings page background and sidebar.
        public static let pageBackground = Color(nsColor: .windowBackgroundColor)
        public static let separator = Color.primary.opacity(0.08)
        /// Line icons at the start of rows.
        public static let icon = Color.secondary
        /// Unselected blocks in layout glyphs.
        public static let glyphInactive = Color.primary.opacity(0.3)

        public static let textPrimary = Color.primary
        public static let textSecondary = Color.primary.opacity(0.86)
        public static let textTertiary = Color.primary.opacity(0.45)
        /// Error / failed action text (system red, adapts light/dark).
        public static let destructive = Color(nsColor: .systemRed)
    }
}

private extension Color {
    init(calibratedRed red: Double, green: Double, blue: Double) {
        self.init(red: red, green: green, blue: blue)
    }
}

/// Primary button: solid brand blue, at most one per page.
struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DesignTokens.fontBody, weight: .medium))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, DesignTokens.spacingMd)
            .frame(minHeight: DesignTokens.controlHeight)
            .background(isEnabled ? DesignTokens.Colors.accent.opacity(configuration.isPressed ? 0.8 : 1) : DesignTokens.Colors.secondaryFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Secondary button: black 4% (dark: white 6%) fill, no stroke.
struct DSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DesignTokens.fontBody, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.spacingMd)
            .frame(minHeight: DesignTokens.controlHeight)
            .background(configuration.isPressed ? DesignTokens.Colors.secondaryFillPressed : DesignTokens.Colors.secondaryFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Soft 24pt fades at the scroll ends that still have content beyond them (same as the toolbar).
struct OverflowEdgeFade: ViewModifier {
    static let length: CGFloat = 24
    @State private var fadeTop = false
    @State private var fadeBottom = false
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    let top = geometry.contentOffset.y + geometry.contentInsets.top
                    let maxOffset = geometry.contentSize.height - geometry.containerSize.height
                    return [top > 0.5, top < maxOffset - 0.5]
                } action: { _, edges in
                    fadeTop = edges[0]; fadeBottom = edges[1]
                }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [fadeTop ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.length)
                        Color.black
                        LinearGradient(colors: [.black, fadeBottom ? .clear : .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.length)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func overflowEdgeFade() -> some View { modifier(OverflowEdgeFade()) }
    /// `Colors.card` fill plus the light-only 0.5pt `cardEdge` stroke.
    func cardSurface(radius: CGFloat = DesignTokens.radiusMd) -> some View {
        background(DesignTokens.Colors.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardEdge, lineWidth: 0.5).allowsHitTesting(false))
    }
}
