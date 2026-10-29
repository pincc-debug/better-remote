import SwiftUI
import RemoteFitCore

struct ResolutionPanelView: View {
    @ObservedObject var model: ControlPanelModel
    let close: () -> Void
    /// 还原本机: restore the Mac's own display (formerly the toolbar's 重置 button).
    let restore: () -> Void
    /// Reports the natural content height so the panel can shrink to fit and hug its dock edge.
    let onContentHeight: (CGFloat) -> Void
    @State private var isHoveringRestore = false
    private let firstPresetID: String?

    init(model: ControlPanelModel, close: @escaping () -> Void, restore: @escaping () -> Void = {}, onContentHeight: @escaping (CGFloat) -> Void = { _ in }) {
        self.model = model
        self.close = close
        self.restore = restore
        self.onContentHeight = onContentHeight
        firstPresetID = model.preferences.selectedCustomID
    }

    private var presets: [CustomPreset] {
        let all = model.preferences.customPresets
        guard let first = all.first(where: { $0.id == firstPresetID }) else { return all }
        return [first] + all.filter { $0.id != first.id }
    }

    private var contentAlignment: Alignment {
        switch model.preferences.toolbarSide {
        case .right: return .topTrailing
        case .bottom: return .bottomLeading
        default: return .topLeading
        }
    }

    private let scalePresets: [(title: String, percent: Int)] = [
        ("更大文字", 120), ("较大文字", 110), ("默认", 100), ("更多空间", 90), ("最多空间", 80)
    ]

    var body: some View {
        VStack(spacing: DesignTokens.spacingMd) {
            // Scrollable Content
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.spacingLg) {
                    // Custom Presets Grid
                    VStack(alignment: .leading, spacing: DesignTokens.spacingSm) {
                        HStack(spacing: DesignTokens.spacingSm) {
                            Text("规格")
                                .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                            if model.applied == nil {
                                Text("未启用")
                                    .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.textSecondary.opacity(0.75))
                            }
                        }

                        let columns = max(1, min(3, Int((min(geometry.size.width, 500) + 16) / 110)))
                        // Plain reading order on every dock: the last-used spec leads row one, rows fill 3, 3, 1.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.spacingSm), count: columns), spacing: DesignTokens.spacingSm) {
                            ForEach(presets.indices, id: \.self) { index in
                                let preset = presets[index]
                                let selected = isAppliedCustom(preset.id)
                                Button { selectCustom(preset.id, alreadySelected: selected) } label: {
                                    SpecCard(preset: preset, selected: selected)
                                }
                                .buttonStyle(.plain)
                                // Pixels live only in the hover tip: the grid is for picking, sizes are set in 设置.
                                .help(SpecCard.help(preset))
                                .accessibilityValue(Text(verbatim: preset.sizeLabel))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }

                    // Display Scaling Container
                    VStack(alignment: .leading, spacing: DesignTokens.spacingSm) {
                        Text("显示大小")
                            .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        // System segmented look: grey track, white thumb, primary text.
                        HStack(spacing: 2) {
                            ForEach(scalePresets, id: \.percent) { preset in
                                let isCurrent = model.adjustment.scalePercent == preset.percent
                                let isApplied = model.applied != nil && isCurrent
                                Button { model.onScale(preset.percent) } label: {
                                    // The floating panel shows no numbers: a letter whose size follows the setting.
                                    Text("A")
                                        .font(.system(size: Self.letterSize(preset.percent), weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background {
                                            if isCurrent {
                                                RoundedRectangle(cornerRadius: DesignTokens.radiusSm, style: .continuous)
                                                    .fill(DesignTokens.Colors.segmentThumb)
                                                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
                                                    .opacity(isApplied ? 1 : 0.6)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(model.adjustment.settingScale(preset.percent) == nil)
                                .accessibilityLabel(preset.title)
                                .accessibilityAddTraits(isApplied ? .isSelected : [])
                                .help(preset.title)
                            }
                        }
                        .padding(2)
                        .background(
                            DesignTokens.Colors.segmentTrack,
                            in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                        )
                    }

                    if let detail = model.detail {
                        Text(detail)
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.orange)
                    }

                    if let hint = model.identifyHint {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(hint.message)
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.Colors.textSecondary.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                            if let title = hint.actionTitle, let action = hint.action {
                                Button(title) { model.onIdentifyHintAction(action) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.Colors.accent)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    // 还原本机 sits last, text only, below a divider.
                    Divider()
                    Button(action: restore) {
                        Label {
                            Text("还原本机")
                        } icon: {
                            // Every 重置 / 还原 entry shares the reset B art (coloured even at this 13pt label size).
                            IconArt.coloredImage(FloatingAction.restoreDisplay.symbol, pointSize: DesignTokens.fontBody)
                        }
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusLg, style: .continuous))
                    }
                    .buttonStyle(RestoreButtonStyle(hovering: isHoveringRestore))
                    .pointerHover("resolution:restore") { isHoveringRestore = $0 }
                    .accessibilityLabel("还原本机")
                }
                .padding(.bottom, 2)
                .frame(maxWidth: 500)
                .background {
                    GeometryReader { content in
                        Color.clear
                            .onAppear { onContentHeight(content.size.height + DesignTokens.spacingLg * 2) }
                            .onChange(of: content.size.height) { _, height in onContentHeight(height + DesignTokens.spacingLg * 2) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: contentAlignment)
            }
            .scrollIndicators(.never, axes: .vertical)
            .defaultScrollAnchor(model.preferences.toolbarSide == .bottom ? .bottom : .top)
            .overflowEdgeFade()
            }
        }
        .padding(DesignTokens.spacingLg)
        .disabled(model.terminating || model.applying)
        .onExitCommand(perform: close)
    }

    /// Letter sizes stepping through the type scale: 11 … 20.
    private static func letterSize(_ percent: Int) -> CGFloat {
        switch percent {
        case ..<85: return DesignTokens.fontCaption
        case ..<95: return DesignTokens.fontBody
        case ..<105: return DesignTokens.fontEmphasis
        case ..<115: return 17
        default: return DesignTokens.fontTitle
        }
    }

    private func isAppliedCustom(_ id: String) -> Bool {
        guard let applied = model.applied, applied == model.preferences.dimensions else { return false }
        return model.preferences.selectedCustomID == id
    }

    private func selectCustom(_ id: String, alreadySelected: Bool) {
        if alreadySelected { close(); return }
        model.onCustom(id)
    }
}

/// Full-width secondary button (radius 14): black 4% (dark white 6%), darker on hover / press, no stroke.
private struct RestoreButtonStyle: ButtonStyle {
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || hovering ? DesignTokens.Colors.secondaryFillPressed : DesignTokens.Colors.secondaryFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusLg, style: .continuous))
    }
}

/// One card in the panel's 规格 picking grid: screen shape and name only, centred with equal space above and below.
/// The size line stays in 设置 (spec list, editor); here it only shows in the hover tip.
struct SpecCard: View {
    static let height: CGFloat = 64
    static let glyphSpacing: CGFloat = 6
    static let nameFont = Font.system(size: DesignTokens.fontBody, weight: .medium)
    static func help(_ preset: CustomPreset) -> String { preset.sizeLabel }

    let preset: CustomPreset
    let selected: Bool

    var body: some View {
        VStack(spacing: Self.glyphSpacing) {
            ScreenGlyph(dimensions: preset.dimensions(.standard), selected: selected, maximumWidth: 34, maximumHeight: 20, strokeOpacity: 0.65)
            Text(preset.title)
                .font(Self.nameFont)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, DesignTokens.spacingXs)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .cardSurface()
        // Selected: one cue only, a 2pt brand stroke (plus the blue screen glyph).
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                .strokeBorder(selected ? DesignTokens.Colors.accent : Color.clear,
                              lineWidth: DesignTokens.selectedStroke)
        )
        .contentShape(Rectangle())
    }
}
