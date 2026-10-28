import AppKit
import SwiftUI
import RemoteFitCore

/// One choice in a `GlassDropdown`.
struct GlassDropdownItem<ID: Hashable & Sendable>: Identifiable, Equatable {
    let id: ID
    let title: String
}

// Keep keyboard focus in the parent: its resign-key observer dismisses the menu.
// Keyboard navigation is handled by the controller's local event monitor.
private final class GlassDropdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Renders the menu inline under the trigger instead of in a floating panel (offscreen review renders only).
private struct GlassDropdownPreviewOpenKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var glassDropdownPreviewOpen: Bool {
        get { self[GlassDropdownPreviewOpenKey.self] }
        set { self[GlassDropdownPreviewOpenKey.self] = newValue }
    }
}

/// Custom dropdown in the app's glass style, replacing the native pop-up button.
/// Trigger: rounded field with the current value and a chevron. Menu: glass panel below the trigger
/// (above when there is no room), hover / keyboard highlight, brand-blue checkmark on the selected row.
/// Esc or a click outside dismisses; ↑ ↓ ⏎ navigate; VoiceOver reads label and value.
struct GlassDropdown<ID: Hashable & Sendable>: View {
    let label: String
    let items: [GlassDropdownItem<ID>]
    let selection: ID?
    var placeholder = "请选择"
    var minWidth: CGFloat = 0
    var flexibleWidth = false
    let onSelect: (ID) -> Void

    @StateObject private var controller = GlassDropdownController<ID>()
    @State private var hovering = false
    @Environment(\.glassDropdownPreviewOpen) private var previewOpen

    private var title: String { items.first { $0.id == selection }?.title ?? placeholder }
    private var isOpen: Bool { controller.state.isOpen || previewOpen }

    var body: some View {
        Button {
            controller.toggle(label: label, items: items, selected: selection, onSelect: onSelect)
        } label: {
            HStack(spacing: DesignTokens.spacingSm) {
                Text(title)
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundStyle(selection == nil ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: DesignTokens.fontCaption, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.icon)
            }
            .padding(.horizontal, DesignTokens.spacingMd)
            .frame(minWidth: minWidth, minHeight: DesignTokens.controlHeight)
            .background(hovering || isOpen ? DesignTokens.Colors.secondaryFillPressed : DesignTokens.Colors.secondaryFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: !flexibleWidth, vertical: true)
        .onHover { hovering = $0 }
        .background(GlassDropdownAnchor { controller.anchor = $0 })
        .overlay(alignment: .topLeading) {
            if previewOpen {
                GlassDropdownMenu(items: items, state: previewState, select: { _ in }, hover: { _ in })
                    // Same rule as the real panel: never narrower than the trigger.
                    .frame(minWidth: GlassDropdownController<ID>.menuWidth(items), maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.radiusLg, style: .continuous))
                    .shadow(color: .black.opacity(Double(DesignTokens.dropdownShadowOpacity)), radius: DesignTokens.dropdownShadowRadius)
                    .offset(y: DesignTokens.controlHeight + DesignTokens.spacingXs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(title)
        .accessibilityHint("弹出选项")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.toggle(label: label, items: items, selected: selection, onSelect: onSelect) }
        .onChange(of: items) { _, next in controller.update(items: next, selected: selection) }
        .onChange(of: selection) { _, next in controller.update(items: items, selected: next) }
        .onDisappear { controller.close() }
    }

    private var previewState: DropdownSelection<ID> {
        var state = DropdownSelection(items: items.map(\.id), selected: selection)
        state.open()
        // Show hover on the row after the selection so both states are visible in review renders.
        if let index = state.highlighted { state.hover(min(index + 1, items.count - 1)) }
        return state
    }
}

/// The rows, shared by the floating panel and preview renders.
struct GlassDropdownMenu<ID: Hashable & Sendable>: View {
    let items: [GlassDropdownItem<ID>]
    let state: DropdownSelection<ID>
    let select: (Int) -> Void
    let hover: (Int) -> Void

    var body: some View {
        let rows = VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = item.id == state.selected
                HStack(spacing: DesignTokens.spacingSm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: DesignTokens.fontCaption, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .opacity(isSelected ? 1 : 0)
                        .frame(width: DesignTokens.fontBody)
                    Text(item.title)
                        .font(.system(size: DesignTokens.fontBody))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignTokens.spacingSm)
                .frame(height: DesignTokens.controlHeight)
                .background(state.highlighted == index ? DesignTokens.Colors.secondaryFillPressed : Color.clear,
                            in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm, style: .continuous))
                .contentShape(Rectangle())
                .onHover { if $0 { hover(index) } }
                .onTapGesture { select(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(index) }
                .id(index)
            }
        }
        .padding(DesignTokens.spacingXs)
        Group {
            if items.count > DesignTokens.dropdownMaxRows {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) { rows }
                        .scrollIndicators(.never)
                        .onChange(of: state.highlighted) { _, index in if let index { proxy.scrollTo(index) } }
                }
            } else { rows }
        }
    }
}

/// Reports the trigger's NSView so the panel can be placed in screen coordinates.
private struct GlassDropdownAnchor: NSViewRepresentable {
    let found: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
final class GlassDropdownController<ID: Hashable & Sendable>: ObservableObject {
    @Published private(set) var state = DropdownSelection<ID>(items: [], selected: nil)
    weak var anchor: NSView?
    private var items: [GlassDropdownItem<ID>] = []
    private var onSelect: (ID) -> Void = { _ in }
    private var panel: GlassDropdownPanel?
    private var host: NSHostingView<GlassDropdownMenu<ID>>?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    /// Widest title plus checkmark column and paddings.
    static func menuWidth(_ items: [GlassDropdownItem<ID>]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: DesignTokens.fontBody)
        let text = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(text) + DesignTokens.fontBody + DesignTokens.spacingSm * 3 + DesignTokens.spacingXs * 2
    }
    static func menuHeight(rows: Int) -> CGFloat {
        CGFloat(min(rows, DesignTokens.dropdownMaxRows)) * DesignTokens.controlHeight + DesignTokens.spacingXs * 2
    }

    func update(items: [GlassDropdownItem<ID>], selected: ID?) {
        self.items = items
        state.update(items: items.map(\.id), selected: selected)
        if state.isOpen { render() }
    }

    func toggle(label: String, items: [GlassDropdownItem<ID>], selected: ID?, onSelect: @escaping (ID) -> Void) {
        if state.isOpen { close(); return }
        self.items = items
        self.onSelect = onSelect
        state.update(items: items.map(\.id), selected: selected)
        open(label: label)
    }

    private func open(label: String) {
        guard let anchor, let window = anchor.window, let screen = window.screen ?? NSScreen.main, !items.isEmpty else { return }
        state.open()
        let trigger = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        // menuFrame widens this to at least the trigger width.
        let size = CGSize(width: Self.menuWidth(items), height: Self.menuHeight(rows: items.count))
        let frame = DropdownSelection<ID>.menuFrame(trigger: trigger, size: size, gap: DesignTokens.spacingXs, bounds: screen.visibleFrame)
        let panel = GlassDropdownPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.title = label
        panel.setAccessibilityRole(.menu)
        panel.setAccessibilityLabel(label)
        let host = NSHostingView(rootView: menu)
        host.sizingOptions = []
        let glass = NativeGlassView(content: host, cornerRadius: DesignTokens.radiusLg, frame: CGRect(origin: .zero, size: frame.size),
                                    contentBackdrop: DesignTokens.NS.glassBackdrop)
        panel.contentView = glass
        panel.appearance = window.effectiveAppearance
        panel.setFrame(frame, display: true)
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        self.panel = panel
        self.host = host
        installMonitors(parent: window, trigger: trigger)
    }

    private var menu: GlassDropdownMenu<ID> {
        GlassDropdownMenu(items: items, state: state,
                          select: { [weak self] index in self?.commit(index) },
                          hover: { [weak self] index in self?.hover(index) })
    }

    private func render() { host?.rootView = menu }

    private func hover(_ index: Int) { state.hover(index); render() }

    private func commit(_ index: Int?) {
        let changed = state.commit(index)
        close()
        if let changed { onSelect(changed) }
    }

    func close() {
        state.close()
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil; host = nil
    }

    private func installMonitors(parent: NSWindow, trigger: CGRect) {
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let code = event.keyCode
            let consumed = MainActor.assumeIsolated { self?.handleKey(code) ?? false }
            return consumed ? nil : event
        }) { monitors.append(keys) }
        if let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let number = event.windowNumber
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, number != panel.windowNumber else { return false }
                self.close()
                // A click on the trigger only closes; swallow it so the button does not reopen the menu.
                return trigger.contains(NSEvent.mouseLocation)
            }
            return swallow ? nil : event
        }) { monitors.append(clicks) }
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.close() }
        }) { monitors.append(outside) }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    /// ↑ ↓ ⏎ / Enter / Space and Esc while open; other keys pass through.
    private func handleKey(_ code: UInt16) -> Bool {
        guard state.isOpen, let key = DropdownKey(keyCode: code) else { return false }
        switch key {
        case .down: state.moveDown(); render()
        case .up: state.moveUp(); render()
        case .commit: commit(nil)
        case .cancel: close()
        }
        return true
    }
}
