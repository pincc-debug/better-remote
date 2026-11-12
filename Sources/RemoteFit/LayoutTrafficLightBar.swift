import AppKit
import Combine
import SwiftUI
import RemoteFitCore

@MainActor
final class LayoutTrafficLightModel: ObservableObject {
    @Published var state = LayoutTrafficLights.State.unavailable
    var perform: (WindowControl) -> Void = { _ in }
}

/// Red, yellow, and green controls for the front window, plus its title.
struct LayoutTrafficLightBar: View {
    let state: LayoutTrafficLights.State
    let perform: (WindowControl) -> Void

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: LayoutTrafficLights.centerSpacing - LayoutTrafficLights.hit) {
                ForEach(WindowControl.allCases, id: \.rawValue) { control in
                    TrafficLightButton(control: control, enabled: state.operable, toolTip: state.toolTip(for: control)) {
                        perform(control)
                    }
                }
            }
            .fixedSize()
            Text(state.caption)
                .font(.system(size: LayoutTrafficLights.captionPointSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Middle ellipsis, the on-screen form of `LayoutTrafficLights.middleTruncated`.
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: LayoutTrafficLights.rowHeight)
        .accessibilityElement(children: .contain)
    }
}

/// 1px rule in the flyout's hairline colour. Resolved for the SwiftUI colour scheme so light and dark previews match the panel.
struct LayoutFlyoutSeparator: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Self.color(for: colorScheme))
                .frame(height: DesignTokens.hairline(scale: NSScreen.main?.backingScaleFactor ?? 2))
        }
        .frame(height: LayoutTrafficLights.separatorBand)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    /// Same colour as `DesignTokens.NS.toolbarSurfaceHairline`, baked for `scheme` so a preview's colour scheme wins over the app appearance.
    /// Success is `usingColorSpace(.sRGB)` returning a colour. `getRed` fills the components and its result is unused (macOS 27 SDK returns `Void`).
    static func color(for scheme: ColorScheme) -> Color {
        let fallback = scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(DesignTokens.NS.toolbarLightHairlineAlpha)
        guard let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) else { return fallback }
        var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)?
        appearance.performAsCurrentDrawingAppearance {
            guard let resolved = DesignTokens.NS.toolbarSurfaceHairline.usingColorSpace(.sRGB) else { return }
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            components = (red, green, blue, alpha)
        }
        guard let components else { return fallback }
        return Color(red: components.red, green: components.green, blue: components.blue, opacity: components.alpha)
    }
}

private struct TrafficLightButton: View {
    let control: WindowControl
    let enabled: Bool
    let toolTip: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let rgb = LayoutTrafficLights.rgb(control)
        Button(action: { if enabled { action() } }) {
            Circle()
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: LayoutTrafficLights.diameter, height: LayoutTrafficLights.diameter)
                .overlay {
                    Image(systemName: control.glyph)
                        .font(.system(size: LayoutTrafficLights.glyphPointSize, weight: .bold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.black.opacity(LayoutTrafficLights.glyphOpacity))
                }
                .clipShape(Circle())
                .frame(width: LayoutTrafficLights.hit, height: LayoutTrafficLights.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(TrafficLightPressStyle(enabled: enabled, hovering: hovering))
        .focusEffectDisabled()
        .opacity(enabled ? 1 : LayoutTrafficLights.disabledOpacity)
        .pointerHover("layout-traffic-\(control.rawValue)") { hovering = enabled && $0 }
        .onChange(of: enabled) { _, now in if !now { hovering = false } }
        .help(toolTip)
        .accessibilityLabel(toolTip)
        .accessibilityIdentifier("layout-traffic-\(control.rawValue)")
        .accessibilityRespondsToUserInteraction(enabled)
    }
}

/// Darkens the circle only. No tile-style grey wash behind the hit target.
private struct TrafficLightPressStyle: ButtonStyle {
    let enabled: Bool
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        let shade = !enabled ? 0 : (configuration.isPressed ? LayoutTrafficLights.pressedShade : (hovering ? LayoutTrafficLights.hoverShade : 0))
        configuration.label
            .overlay {
                Circle()
                    .fill(Color.black.opacity(shade))
                    .frame(width: LayoutTrafficLights.diameter, height: LayoutTrafficLights.diameter)
                    .allowsHitTesting(false)
            }
    }
}
