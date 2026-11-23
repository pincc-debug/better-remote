import AppKit
import SwiftUI
import RemoteFitCore

struct UUScrollSpeedSettings: View {
    @Binding var percent: Int
    var embedded = false

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SettingsView.settingIcon("gauge.with.dots.needle.33percent")
                Text("滚动速度").font(.system(size: DesignTokens.fontBody, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(percent)%").monospacedDigit().font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accent)
            }
            Slider(value: Binding(
                get: { Double(percent) },
                set: { newValue in
                    let next = min(100, max(1, Int(newValue.rounded())))
                    guard next != percent else { return }
                    percent = next
                    Self.hapticTick()
                }
            ), in: 1...100)
                .tint(DesignTokens.Colors.accent)
                .accessibilityLabel("UU 滚动速度")
                .accessibilityValue("原速的 \(percent)%")
            HStack {
                Text("1% · 更慢")
                Spacer()
                Text("100% · 原速")
            }.font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
            HStack(spacing: DesignTokens.spacingSm) {
                ForEach([5, 10, 25, 100], id: \.self) { value in
                    let isSelected = value == percent
                    Button {
                        if value != percent {
                            percent = value
                        }
                        Self.hapticTick()
                    } label: {
                        Text(value == 100 ? "原速" : "\(value)%")
                            .font(.system(size: DesignTokens.fontCaption, weight: isSelected ? .semibold : .medium)).monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(
                                isSelected ? DesignTokens.Colors.accentFill : DesignTokens.Colors.secondaryFill,
                                in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                                    .strokeBorder(isSelected ? DesignTokens.Colors.accent : Color.clear, lineWidth: DesignTokens.selectedStroke)
                            )
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(value == 100 ? "设为原速" : "设为原速的 \(value)%")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(14)
    }

    var body: some View {
        if embedded {
            content
        } else {
            SettingsView.settingCard { content }
        }
    }

    /// Force Touch / trackpad tick when the stepped percent changes (or a preset is tapped).
    private static func hapticTick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
