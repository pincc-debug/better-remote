import AppKit
import Combine
import SwiftUI
import RemoteFitCore

@MainActor
final class LayoutTrafficLightModel: ObservableObject {
    @Published var state = LayoutTrafficLights.State.unavailable
    var perform: (WindowControl) -> Void = { _ in }
}

/// Close, minimize, and full-screen for the front window. Neutral buttons, no window-name text.
struct LayoutTrafficLightBar: View {
    let state: LayoutTrafficLights.State
    let perform: (WindowControl) -> Void

    var body: some View {
        HStack(spacing: LayoutTrafficLights.buttonSpacing) {
            ForEach(WindowControl.allCases, id: \.rawValue) { control in
                WindowActionButton(
                    id: control.rawValue,
                    title: state.title(for: control),
                    symbol: state.symbol(for: control),
                    enabled: state.operable,
                    toolTip: state.toolTip(for: control)
                ) {
                    perform(control)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: LayoutTrafficLights.rowHeight)
        .accessibilityElement(children: .contain)
    }
}

/// 1px rule in the flyout's hairline colour, with 8pt above and below.
struct LayoutFlyoutSeparator: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Rectangle()
            .fill(Self.color(for: colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.hairline(scale: NSScreen.main?.backingScaleFactor ?? 2))
            .padding(.vertical, LayoutTrafficLights.separatorGap)
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

private struct WindowActionButton: View {
    let id: String
    let title: String
    let symbol: String
    let enabled: Bool
    let toolTip: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: LayoutTrafficLights.labelSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: LayoutTrafficLights.iconPointSize))
                Text(title)
                    .font(.system(size: LayoutTrafficLights.labelPointSize, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: LayoutTrafficLights.rowHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
        }
        .buttonStyle(WindowActionPressStyle(enabled: enabled, hovering: hovering))
        .focusEffectDisabled()
        .opacity(enabled ? 1 : LayoutTrafficLights.disabledOpacity)
        .pointerHover("layout-action-\(id)") { hovering = enabled && $0 }
        .onChange(of: enabled) { _, now in if !now { hovering = false } }
        .modifier(OptionalHelp(text: toolTip))
        .accessibilityLabel(title)
        .accessibilityIdentifier("layout-action-\(symbol)")
        .accessibilityRespondsToUserInteraction(enabled)
    }

    private var fill: Color {
        colorScheme == .dark
            ? Color.white.opacity(LayoutTrafficLights.darkFillOpacity)
            : Color.black.opacity(LayoutTrafficLights.lightFillOpacity)
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?
    @ViewBuilder func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

/// Layout-tile wash: primary 8% on hover, 12% while pressed. No colour of its own.
private struct WindowActionPressStyle: ButtonStyle {
    let enabled: Bool
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        let overlay = !enabled ? 0 : (configuration.isPressed ? LayoutTrafficLights.pressedOverlay : (hovering ? LayoutTrafficLights.hoverOverlay : 0))
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                    .fill(Color.primary.opacity(overlay))
                    .allowsHitTesting(false)
            }
    }
}
