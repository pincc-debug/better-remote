import SwiftUI
import RemoteFitCore

struct UUScrollSpeedSettings: View {
    @ObservedObject var model: ControlPanelModel
    private var percent: Int { model.preferences.uuScrollSpeedPercent }

    var body: some View {
        SettingsView.settingCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("滚动速度").font(.system(size: DesignTokens.fontBody, weight: .medium))
                    Spacer()
                    Text("\(percent)%").monospacedDigit().font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }
                Slider(value: Binding(get: { Double(percent) }, set: { model.onUUScrollSpeedPercent(Int($0.rounded())) }),
                       in: 1...100, step: 1)
                    .accessibilityLabel("UU 滚动速度")
                    .accessibilityValue("原速的 \(percent)%")
                HStack {
                    Text("1% · 更慢")
                    Spacer()
                    Text("100% · 原速")
                }.font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([5, 10, 25, 100], id: \.self) { value in
                        Button { model.onUUScrollSpeedPercent(value) } label: {
                            Text(value == 100 ? "原速" : "\(value)%")
                                .font(.system(size: DesignTokens.fontCaption, weight: .medium)).monospacedDigit()
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(percent == value ? DesignTokens.Colors.accent.opacity(0.12) : DesignTokens.Colors.secondaryFill,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(value == 100 ? "设为原速" : "设为原速的 \(value)%")
                            .accessibilityAddTraits(percent == value ? [.isSelected] : [])
                    }
                }
            }
            .padding(14)
        }
    }
}
