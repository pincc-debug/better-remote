import SwiftUI
import AppKit
import RemoteFitCore

struct ShortcutEditor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dialogLimitOverride) private var dialogLimitOverride
    let id: String
    let enabled: Bool
    let onSave: (NamedShortcut) -> Bool
    let onCancel: () -> Void
    let onDelete: (() -> Bool)?
    @State private var confirmingDelete = false
    @State private var name: String
    @State private var key: ShortcutKey?
    @State private var icon: ShortcutIcon
    @State private var useRecorder = false
    @State private var showsIconPicker = false
    @State private var userExplicitlySelectedIcon: Bool
    @State private var error: String?
    /// Natural heights of the pinned chrome and the scrolling middle, so the sheet hugs its content.
    @State private var chromeHeight: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0

    init(shortcut: NamedShortcut, onSave: @escaping (NamedShortcut) -> Bool, onCancel: @escaping () -> Void, onDelete: (() -> Bool)? = nil) {
        id = shortcut.id
        enabled = shortcut.enabled
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _name = State(initialValue: shortcut.name)
        _key = State(initialValue: shortcut.key.isValid ? shortcut.key : nil)
        let resolvedIcon = shortcut.icon == .keyboard ? (ShortcutIcon.suggested(for: shortcut.name, keyLabel: shortcut.key.label) ?? .keyboard) : shortcut.icon
        _icon = State(initialValue: resolvedIcon)
        _userExplicitlySelectedIcon = State(initialValue: shortcut.icon != .keyboard)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .background(Self.heightReader { chromeHeight = $0 })
            Divider()

            // Only the middle scrolls; header and footer stay pinned.
            ScrollView {
                VStack(spacing: 16) {
                    nameSection
                    keySection
                    iconSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Self.heightReader { bodyHeight = $0 })
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(-1)

            // Footer
            Divider()
            footerView
                .fixedSize(horizontal: false, vertical: true)
                .background(Self.heightReader { footerHeight = $0 })
        }
        .frame(width: min(460, DialogLimit.current(dialogLimitOverride).width))
        // The key window is this sheet once it opens. Using its current height as
        // a limit feeds the last layout back into the next and progressively shrinks it.
        .frame(height: min(preferredHeight, DialogLimit.current(dialogLimitOverride).height))
        .onExitCommand(perform: onCancel)
        .background(DesignTokens.Colors.pageBackground)
        .alert(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "删除此操作？" : "删除「\(name)」？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if onDelete?() == false { error = "删除失败，请重试" }
            }
        }
    }

    @State private var footerHeight: CGFloat = 0

    /// Content-hugging height once measured; the previous fixed sizes until then.
    private var preferredHeight: CGFloat {
        guard bodyHeight > 0, chromeHeight > 0, footerHeight > 0 else { return (showsIconPicker ? 610 : 450) + (error == nil ? 0 : 40) }
        return (chromeHeight + footerHeight + bodyHeight + 2).rounded(.up)
    }

    private static func heightReader(_ update: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { update(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in update(height) }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            Text(onDelete == nil ? "添加操作" : "编辑操作")
                .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button(action: onCancel) { IconArt.closeGlyph() }
            .buttonStyle(.plain)
            .help("关闭，不保存修改")
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Name and Icon

    private var nameSection: some View {
        HStack(spacing: 10) {
            Text("名称")
                .font(.system(size: DesignTokens.fontBody, weight: .medium))
                .frame(width: 50, alignment: .leading)
            TextField("操作名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.regular)
                .onChange(of: name) { _, newName in
                    if !userExplicitlySelectedIcon, let suggested = ShortcutIcon.suggested(for: newName, keyLabel: key?.label ?? "") {
                        icon = suggested
                    }
                }
        }
        .padding(.vertical, 4)
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("图标")
                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                IconArt.image(icon.rawValue, pointSize: DesignTokens.fontEmphasis)
                    .frame(width: 24)
                Text(icon.title)
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        showsIconPicker.toggle()
                    }
                } label: {
                    Text(showsIconPicker ? "收起" : "更换")
                        .font(.system(size: DesignTokens.fontBody, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Keep the 44pt hit area without letting it push the row taller than the others.
                .padding(.vertical, -13)
                .accessibilityLabel(showsIconPicker ? "收起图标选择" : "更换图标")
            }
            if showsIconPicker {
                IconPickerView(selected: icon) { selected in
                    icon = selected
                    userExplicitlySelectedIcon = true
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        showsIconPicker = false
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Key Section

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("按键组合")
                    .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $useRecorder) {
                    Text("手动配置").tag(false)
                    Text("按键录制").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            VStack(alignment: .leading, spacing: 12) {
                if useRecorder {
                    VStack(alignment: .leading, spacing: 8) {
                        ShortcutRecorder(key: $key)
                            .frame(height: 52)
                            .accessibilityLabel("录制快捷键")
                        Text("点击输入框后按下快捷键")
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Text("主按键")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                            .frame(width: 50, alignment: .leading)
                        Picker("", selection: Binding(get: { key?.code ?? UInt16.max }, set: { setManualKey($0, modifiers: key?.modifiers ?? 0) })) {
                            Text("请选择按键…").tag(UInt16.max)
                            ForEach(Self.keys, id: \.0) { entry in
                                Text(entry.1).tag(entry.0)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("修饰键")
                            .font(.system(size: DesignTokens.fontBody, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            keycapButton("⌘", title: "Command", mask: 1 << 20)
                            keycapButton("⌥", title: "Option", mask: 1 << 19)
                            keycapButton("⌃", title: "Control", mask: 1 << 18)
                            keycapButton("⇧", title: "Shift", mask: 1 << 17)
                        }
                        .disabled(key == nil || ShortcutEventPlan.mask(for: key?.code ?? UInt16.max) != nil)
                    }
                }

                // Current keycap preview badge
                HStack(spacing: 6) {
                    Text("快捷键")
                        .font(.system(size: DesignTokens.fontBody))
                        .foregroundStyle(.secondary)
                    if let key, key.isValid {
                        Text(key.label)
                            .font(.system(size: DesignTokens.fontBody, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.accentFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm, style: .continuous))
                            .foregroundStyle(DesignTokens.Colors.accent)
                    } else {
                        Text("未设定")
                            .font(.system(size: DesignTokens.fontBody))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 8) {
            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(error).font(.system(size: DesignTokens.fontBody)).foregroundStyle(.red)
                    Spacer()
                }
            }

            HStack {
                if onDelete != nil {
                    Button("删除", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button("保存") {
                    guard let key else { return }
                    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !onSave(.init(id: id, name: cleanName, key: key, mode: .press, icon: icon, enabled: enabled)) {
                        error = "保存失败，请重试"
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(key == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 32)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Keycap Button

    private func keycapButton(_ symbol: String, title: String, mask: UInt64) -> some View {
        let isPressed = (key?.modifiers ?? 0) & mask != 0
        return Button {
            guard let key else { return }
            setManualKey(key.code, modifiers: key.modifiers ^ mask)
        } label: {
            HStack(spacing: DesignTokens.spacingXs) {
                Text(symbol)
                    .font(.system(size: DesignTokens.fontBody, weight: .semibold))
                Text(title)
                    .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .background(
                isPressed ? DesignTokens.Colors.accentFill : DesignTokens.Colors.secondaryFill,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm, style: .continuous)
            )
            .foregroundStyle(isPressed ? DesignTokens.Colors.accent : DesignTokens.Colors.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setManualKey(_ code: UInt16, modifiers: UInt64) {
        guard let entry = Self.keys.first(where: { $0.0 == code }) else { key = nil; return }
        if let mask = ShortcutEventPlan.mask(for: code) {
            key = .init(code: code, modifiers: mask, label: entry.1)
            return
        }
        let flags = ShortcutEventPlan.mask(for: key?.code ?? UInt16.max) == nil ? modifiers : 0
        let symbols: [(UInt64, String)] = [(1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘")]
        let prefix = symbols.filter { flags & $0.0 != 0 }.map { $0.1 }.joined()
        let newKey = ShortcutKey(code: code, modifiers: flags, label: prefix + entry.1)
        key = newKey
        if !userExplicitlySelectedIcon, let suggested = ShortcutIcon.suggested(for: name, keyLabel: newKey.label) {
            icon = suggested
        }
    }

    private static let keys: [(UInt16, String)] = [
        (58, "Option 左"),
        (61, "Option 右"),
        (55, "Command 左"),
        (54, "Command 右"),
        (59, "Control 左"),
        (62, "Control 右"),
        (56, "Shift 左"),
        (60, "Shift 右"),
        (63, "Fn"),
        (53, "Esc"),
        (48, "Tab"),
        (49, "空格"),
        (36, "回车"),
        (51, "删除"),
        (123, "←"),
        (124, "→"),
        (125, "↓"),
        (126, "↑"),
        (0, "A"),
        (11, "B"),
        (8, "C"),
        (2, "D"),
        (14, "E"),
        (3, "F"),
        (5, "G"),
        (4, "H"),
        (34, "I"),
        (38, "J"),
        (40, "K"),
        (37, "L"),
        (46, "M"),
        (45, "N"),
        (31, "O"),
        (35, "P"),
        (12, "Q"),
        (15, "R"),
        (1, "S"),
        (17, "T"),
        (32, "U"),
        (9, "V"),
        (13, "W"),
        (7, "X"),
        (16, "Y"),
        (6, "Z"),
        (29, "0"),
        (18, "1"),
        (19, "2"),
        (20, "3"),
        (21, "4"),
        (23, "5"),
        (22, "6"),
        (26, "7"),
        (28, "8"),
        (25, "9"),
        (122, "F1"),
        (120, "F2"),
        (99, "F3"),
        (118, "F4"),
        (96, "F5"),
        (97, "F6"),
        (98, "F7"),
        (100, "F8"),
        (101, "F9"),
        (109, "F10"),
        (103, "F11"),
        (111, "F12")
    ]
}
