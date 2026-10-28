import AppKit
import QuartzCore
import SwiftUI
import RemoteFitCore

private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ToolbarDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class ToolbarButton: NSButton {
    var onTap: () -> Void = {}
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onDrag: ((CGPoint) -> Void)?
    /// Drag past a small threshold scrolls the custom operations instead of tapping.
    var onScrollDrag: ((CGFloat) -> Void)?
    var dragsHorizontally = false
    var isCircular = false
    var selected = false { didSet { updateColors() } }
    private var lastScroll: CGPoint?
    private let glyph = NSImageView()
    func animateEntrance(delay: TimeInterval, side: ToolbarSide) {
        wantsLayer = true
        guard let layer else { return }
        let dx: CGFloat = side == .right ? 10 : (side == .left ? -10 : 0)
        let dy: CGFloat = side == .top ? 10 : (side == .bottom ? -10 : 0)
        let start = CATransform3DConcat(CATransform3DMakeTranslation(dx, dy, 0), CATransform3DMakeScale(0.86, 0.86, 1))
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = [NSValue(caTransform3D: start), NSValue(caTransform3D: CATransform3DMakeScale(1.035, 1.035, 1)), NSValue(caTransform3D: CATransform3DIdentity)]
        transform.keyTimes = [0, 0.72, 1]
        transform.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        transform.duration = 0.24
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.3; fade.toValue = 1; fade.duration = 0.20
        let group = CAAnimationGroup()
        group.animations = [transform, fade]
        group.duration = 0.24
        group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.fillMode = .backwards
        layer.add(group, forKey: "toolbar-entrance")
    }
    private let caption = NSTextField(labelWithString: "")
    private let labelled: Bool
    private let glyphSize: CGFloat
    private let pointSize: CGFloat
    /// The action's symbol; nil once a real app icon is set.
    private var symbol: String?
    /// Optional glyph centre (from the top); the horizontal footer uses the labelled buttons' centre.
    var glyphCenterY: CGFloat? { didSet { if oldValue != glyphCenterY { needsLayout = true } } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(symbol: String, name: String, showsCaption: Bool = true, largeIcon: Bool = false) {
        labelled = showsCaption
        glyphSize = largeIcon ? 30 : (showsCaption ? 24 : 20)
        pointSize = largeIcon ? 28 : (showsCaption ? 23 : 18)
        self.symbol = symbol
        super.init(frame: .zero)
        title = ""; isBordered = false; focusRingType = .none
        refreshGlyph()
        glyph.contentTintColor = DesignTokens.NS.textPrimary
        glyph.imageScaling = .scaleProportionallyDown
        caption.stringValue = name
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = DesignTokens.NS.textSecondary
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 1
        caption.isHidden = !showsCaption
        addSubview(glyph); addSubview(caption)
        toolTip = name
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(name)
    }
    required init?(coder: NSCoder) { nil }
    func setGlyph(_ image: NSImage) { symbol = nil; glyph.image = image; updateColors() }
    /// Swaps symbol and caption in place (铺满 ⇄ 还原); no state background.
    func update(symbol: String, name: String) {
        guard caption.stringValue != name else { return }
        self.symbol = symbol
        caption.stringValue = name; toolTip = name; setAccessibilityLabel(name)
        updateColors()
    }
    /// Hover comes from the app-wide `PointerHover` owner, never from enter/exit alone.
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var hoverID: String { "toolbar:\(ObjectIdentifier(self).hashValue)" }
    private var hoverObservation: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hoverObservation = nil; PointerHover.shared.left(hoverID); hovering = false; return }
        hoverObservation = PointerHover.shared.$hoveredID.sink { [weak self] id in
            MainActor.assumeIsolated { guard let self else { return }; self.hovering = id == self.hoverID }
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { if isEnabled { PointerHover.shared.moved(over: hoverID) } }
    override func mouseMoved(with event: NSEvent) { if isEnabled { PointerHover.shared.moved(over: hoverID) } }
    override func mouseExited(with event: NSEvent) { PointerHover.shared.left(hoverID) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    /// Style-B art (baked colours: white on the blue selection) when the symbol has it, else the template symbol.
    private func refreshGlyph() {
        guard let symbol else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        glyph.image = BIcons.image(symbol, side: pointSize, style: selected ? .onAccent : .normal, dark: dark)
            ?? IconArt.nsImage(symbol, pointSize: pointSize, weight: .medium)
    }
    private func updateColors() {
        refreshGlyph()
        glyph.contentTintColor = glyph.image?.isTemplate == false ? nil : (selected ? .white : DesignTokens.NS.textPrimary)
        caption.textColor = selected ? .white : DesignTokens.NS.textSecondary
        // Glass is mostly clear now: a soft halo keeps glyphs and captions readable over any background.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let shadow = NSShadow()
            shadow.shadowColor = selected ? nil : DesignTokens.NS.legibilityShadow.usingColorSpace(.deviceRGB)
            shadow.shadowBlurRadius = DesignTokens.legibilityShadowRadius
            shadow.shadowOffset = .zero
            glyph.shadow = shadow
            caption.shadow = shadow
        }
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === glyph || hit === caption ? self : hit
    }
    override func layout() {
        super.layout()
        let glyphY = glyphCenterY.map { $0 - glyphSize / 2 } ?? (labelled ? 9 : (bounds.height - glyphSize) / 2)
        glyph.frame = CGRect(x: (bounds.width - glyphSize) / 2, y: glyphY, width: glyphSize, height: glyphSize)
        caption.frame = CGRect(x: 2, y: 38, width: bounds.width - 4, height: 14)
    }
    override func draw(_ dirtyRect: NSRect) {
        let radius = isCircular ? min(bounds.width, bounds.height) / 2 : DesignTokens.radiusMd
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let fillColor: NSColor
        let strokeColor: NSColor
        if selected {
            fillColor = DesignTokens.NS.buttonActive
            strokeColor = DesignTokens.NS.buttonActiveBorder
        } else if isHighlighted {
            fillColor = DesignTokens.NS.buttonHighlight
            strokeColor = DesignTokens.NS.buttonHighlight
        } else if hovering && isEnabled {
            fillColor = DesignTokens.NS.pedestalBorder
            strokeColor = .clear
        } else {
            // No resting base: every toolbar button shows a background only on hover / press.
            fillColor = .clear
            strokeColor = .clear
        }

        fillColor.setFill()
        path.fill()

        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let start = pointerPosition(for: event)
        let origin = window?.frame.origin ?? .zero
        var dragged = false
        lastScroll = nil
        let savedRelease = onRelease
        defer { onRelease = savedRelease }
        OperationDiagnostics.write("button-down id=\(identifier?.rawValue ?? "handle") window=\(window?.windowNumber ?? 0) eventWindow=\(event.windowNumber) \(OperationDiagnostics.mouseDetails(event, in: self))")
        PointerHover.shared.reset()
        highlight(true); onPress()
        defer { onRelease(); highlight(false); PointerHover.shared.reset() }
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                let inside = containsPointer(for: next)
                OperationDiagnostics.write("button-up id=\(identifier?.rawValue ?? "handle") eventWindow=\(next.windowNumber) inside=\(inside) dragged=\(dragged) \(OperationDiagnostics.mouseDetails(next, in: self))")
                if !dragged, inside { onTap() }
                break
            }
            let mouse = pointerPosition(for: next)
            let delta = dragsHorizontally ? mouse.x - start.x : mouse.y - start.y
            if let onScrollDrag {
                if dragged || abs(delta) > 6 {
                    if !dragged { dragged = true; highlight(false); onRelease(); onRelease = {} }
                    let previous = lastScroll ?? start
                    let step = dragsHorizontally ? mouse.x - previous.x : mouse.y - previous.y
                    // Screen y grows upward; content offset grows as the finger moves up (vertical) or left.
                    onScrollDrag(dragsHorizontally ? -step : step)
                    lastScroll = mouse
                }
                continue
            }
            if let onDrag, abs(delta) > 10 || dragged {
                dragged = true
                highlight(false)
                onDrag(CGPoint(x: origin.x + (dragsHorizontally ? delta : 0),
                               y: origin.y + (dragsHorizontally ? 0 : delta)))
            } else if onDrag == nil {
                let inside = containsPointer(for: next)
                highlight(inside)
            }
        }
    }
    private func containsPointer(for event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = event.windowNumber == window.windowNumber
            ? event.locationInWindow : window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return bounds.contains(convert(point, from: nil))
    }
    private func pointerPosition(for event: NSEvent) -> CGPoint {
        guard let window, event.windowNumber == window.windowNumber else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        OperationDiagnostics.write("button-accessibility id=\(identifier?.rawValue ?? "handle")")
        onPress(); onRelease(); onTap(); return true
    }
}

enum LayoutChoice { case snap(WindowSnap), arrange(WindowArrangement) }

/// Mirrors the native macOS window-layout menu: icon-only tiles, no section title (the divider separates it).
private struct LayoutFlyoutView: View {
    let pick: (LayoutChoice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let arrangeItems: [(LayoutChoice, String, LayoutGlyph.Region)] =
                [(.snap(.fill), "填充", .all([CGRect(x: 0, y: 0, width: 1, height: 1)])),
                 (.snap(.center), "居中", .all([CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8)]))]
                + WindowArrangement.allCases.map { arrangement in
                    let units = arrangement.units
                    return (.arrange(arrangement), arrangement.title, .split(front: units[0], others: Array(units.dropFirst())))
                }
            ForEach(Array(stride(from: 0, to: arrangeItems.count, by: 4)), id: \.self) { start in
                row(Array(arrangeItems[start..<min(start + 4, arrangeItems.count)]))
            }
        }
        // Uniform 12pt inset; 4 × 64 + 3 × 8 + 24 = 304 wide, so every row (the lone last one too) shares one grid.
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func row(_ items: [(LayoutChoice, String, LayoutGlyph.Region)]) -> some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button { pick(item.0) } label: {
                    LayoutGlyph(region: item.2)
                        .frame(width: 64, height: 60)
                        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
                }
                .buttonStyle(LayoutTileStyle())
                .accessibilityLabel(item.1)
                .help(item.1)
            }
        }
    }
}

/// Rounded-rect outline (1.5pt). The block the current window goes to: blue line + blue 24% fill (style B);
/// the other blocks are outline only.
private struct LayoutGlyph: View {
    enum Region {
        case all([CGRect])
        case split(front: CGRect, others: [CGRect])
    }
    let region: Region
    static let currentFillOpacity: Double = 0.24
    static let cellStroke: CGFloat = 1.2
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignTokens.radiusSm, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.6), lineWidth: DesignTokens.glyphStroke)
            GeometryReader { geo in
                let inner = CGRect(origin: .zero, size: geo.size).insetBy(dx: 5, dy: 5)
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    let r = CGRect(x: inner.minX + cell.0.minX * inner.width, y: inner.minY + cell.0.minY * inner.height,
                                   width: cell.0.width * inner.width, height: cell.0.height * inner.height).insetBy(dx: 1, dy: 1)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cell.1 ? Color(nsColor: .systemBlue).opacity(Self.currentFillOpacity) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 1.5)
                            .strokeBorder(cell.1 ? Color(nsColor: .systemBlue) : Color.primary.opacity(0.6), lineWidth: Self.cellStroke))
                        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
            }
        }
        .frame(width: 44, height: 30)
    }
    private var cells: [(CGRect, Bool)] {
        switch region {
        case .all(let rects): rects.map { ($0, true) }
        case .split(let front, let others): [(front, true)] + others.map { ($0, false) }
        }
    }
}

/// Per-app shortcut tiles: same item style as the 窗口 panel (no resting tile, hover/press highlight only).
private struct ApplicationShortcutFlyoutView: View {
    let items: [(symbol: String, name: String)]
    let columns: Int
    let tile: CGSize
    let spacing: CGFloat
    let scrolls: Bool
    let pick: (Int) -> Void
    var body: some View {
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile.width), spacing: spacing), count: max(1, columns)), spacing: spacing) {
            ForEach(items.indices, id: \.self) { index in
                Button { pick(index) } label: {
                    VStack(spacing: 4) {
                        IconArt.image(items[index].symbol, pointSize: 21, weight: .medium).font(.system(size: 21, weight: .medium)).frame(height: 26)
                        Text(items[index].name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: tile.width, height: tile.height)
                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
                }
                .buttonStyle(LayoutTileStyle())
                .accessibilityLabel(items[index].name)
                .help(items[index].name)
            }
        }
        .padding(8)
        if scrolls { ScrollView(.vertical, showsIndicators: false) { grid } } else { grid }
    }
}

private struct LayoutTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .modifier(TileHover(pressed: configuration.isPressed))
    }
}

private struct TileHover: ViewModifier {
    let pressed: Bool
    @State private var hovering = false
    @State private var id = UUID().uuidString
    func body(content: Content) -> some View {
        content
            // Hover 8% (same as the toolbar), pressed 12% while held; hover only from genuine pointer movement.
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                .fill(Color.primary.opacity(pressed ? 0.12 : (hovering ? 0.08 : 0))))
            .pointerHover(id) { hovering = $0 }
    }
}

@MainActor
private final class ToolbarContent: NSView {
    let clip = ToolbarDocumentView()
    let document = ToolbarDocumentView()
    let grip = ToolbarButton(symbol: "line.3.horizontal", name: "移动快捷操作", showsCaption: false)
    let resolution = ToolbarButton(symbol: FloatingAction.resolution.symbol, name: "分辨率", showsCaption: false)
    let settings = ToolbarButton(symbol: "gearshape", name: "设置", showsCaption: false)
    let restore = ToolbarButton(symbol: FloatingAction.restoreDisplay.symbol, name: "重置", showsCaption: false)
    let pedestal = NSBox()
    /// One 布局 button opens the layouts flyout.
    let applicationButton: ToolbarButton?
    let windowButton: ToolbarButton?
    let collapse: ToolbarButton
    let previous: ToolbarButton
    let next: ToolbarButton
    let grid: DesktopToolbarLayout.Grid
    let side: ToolbarSide
    var buttons: [ToolbarButton] = []
    /// Scroll position of the custom operations, in points along the toolbar.
    private(set) var offset: CGFloat = 0
    var onOffsetChange: (CGFloat) -> Void = { _ in }
    override var isFlipped: Bool { true }
    init(frame: NSRect, grid: DesktopToolbarLayout.Grid, side: ToolbarSide, application: NSRunningApplication? = nil) {
        collapse = ToolbarButton(symbol: side.collapseSymbol, name: "收起快捷操作", showsCaption: false)
        previous = ToolbarButton(symbol: side.isHorizontal ? "chevron.left" : "chevron.up", name: "向前滚动", showsCaption: false)
        next = ToolbarButton(symbol: side.isHorizontal ? "chevron.right" : "chevron.down", name: "向后滚动", showsCaption: false)
        self.grid = grid
        self.side = side
        if grid.windowControls {
            let button = ToolbarButton(symbol: "rectangle.split.2x2", name: "布局", showsCaption: false)
            button.identifier = .init("persistent:window")
            windowButton = button
        } else { windowButton = nil }
        if let application {
            let button = ToolbarButton(symbol: "app", name: application.localizedName ?? "应用", showsCaption: false, largeIcon: true)
            if let icon = application.icon { button.setGlyph(icon) }
            button.identifier = .init("persistent:applicationShortcuts")
            applicationButton = button
        } else { applicationButton = nil }
        super.init(frame: frame)
        if let applicationButton { addSubview(applicationButton) }
        pedestal.boxType = .custom
        pedestal.fillColor = DesignTokens.NS.pedestalBorder
        pedestal.borderColor = .clear; pedestal.borderWidth = 0; pedestal.cornerRadius = 0
        addSubview(pedestal)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.addSubview(document)
        addSubview(grip); addSubview(clip); addSubview(collapse)
        resolution.identifier = .init("persistent:resolution")
        settings.identifier = .init("persistent:settings")
        restore.identifier = .init("persistent:restoreDisplay")
        collapse.identifier = .init("persistent:collapse")
        if let windowButton { addSubview(windowButton) }
        addSubview(resolution); addSubview(settings)
        addSubview(previous); addSubview(next)
        previous.isHidden = true
        next.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    /// Single column after a divider: 窗口, 分辨率, 设置, 收起, 重置.
    private var footerButtons: [ToolbarButton] { (applicationButton.map { [$0] } ?? []) + (windowButton.map { [$0] } ?? []) + [resolution, settings, collapse] }
    private var contentLength: CGFloat { max(0, CGFloat(buttons.count) * DesktopToolbarLayout.step - (DesktopToolbarLayout.step - DesktopToolbarLayout.buttonHeight)) }
    private var visibleLength: CGFloat { side.isHorizontal ? clip.bounds.width : clip.bounds.height }
    var maxOffset: CGFloat { max(0, contentLength - visibleLength) }
    func setOffset(_ value: CGFloat, animated: Bool = false) {
        let next = min(max(0, value), maxOffset)
        if abs(next - offset) > 0.5 { PointerHover.shared.reset() }
        offset = next
        let origin = side.isHorizontal ? CGPoint(x: -offset, y: 0) : CGPoint(x: 0, y: -offset)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; document.animator().setFrameOrigin(origin) }
        } else { document.setFrameOrigin(origin) }
        updateArrows()
        onOffsetChange(offset)
    }
    /// Soft fades at the ends that still have content beyond them.
    private func updateArrows() {
        guard let layer = clip.layer else { return }
        let fadeStart = offset > 0.5, fadeEnd = offset < maxOffset - 0.5
        guard fadeStart || fadeEnd else { layer.mask = nil; return }
        let mask = (layer.mask as? CAGradientLayer) ?? CAGradientLayer()
        mask.frame = clip.bounds
        let length = max(1, visibleLength), fade = min(0.25, 24 / length)
        let clear = NSColor.clear.cgColor, solid = NSColor.black.cgColor
        mask.colors = [fadeStart ? clear : solid, solid, solid, fadeEnd ? clear : solid]
        mask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        if side.isHorizontal {
            mask.startPoint = CGPoint(x: 0, y: 0.5); mask.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            // The clip view is flipped; layer y runs top to bottom here.
            mask.startPoint = CGPoint(x: 0.5, y: 0); mask.endPoint = CGPoint(x: 0.5, y: 1)
        }
        layer.mask = mask
    }
    override func scrollWheel(with event: NSEvent) {
        guard maxOffset > 0 else { return super.scrollWheel(with: event) }
        let raw = side.isHorizontal ? (event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY) : event.scrollingDeltaY
        let delta = event.hasPreciseScrollingDeltas ? raw : raw * 16
        setOffset(offset - delta)
    }
    override func layout() {
        super.layout()
        let step = DesktopToolbarLayout.step, height = DesktopToolbarLayout.buttonHeight
        let footer = DesktopToolbarLayout.footerHeight(windowControls: windowButton != nil, applicationShortcut: applicationButton != nil)
        if side.isHorizontal {
            let footerX = bounds.width - footer
            pedestal.frame = CGRect(x: footerX + 2, y: 12, width: 1, height: bounds.height - 24)
            let y = (bounds.height - height) / 2
            for (index, button) in footerButtons.enumerated() {
                button.frame = CGRect(x: footerX + 8 + CGFloat(index) * DesktopToolbarLayout.footerStep, y: y, width: DesktopToolbarLayout.footerButtonHeight, height: height)
                // Labelled glyphs sit at y 9 + 24/2 = 21; centre the footer glyphs on the same line.
                button.glyphCenterY = 21
            }
            let left = DesktopToolbarLayout.customInset; let right = footerX - DesktopToolbarLayout.customInset
            clip.frame = CGRect(x: left, y: y, width: max(1, right - left), height: height)
            document.frame = CGRect(x: -offset, y: 0, width: max(contentLength, clip.bounds.width), height: height)
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: CGFloat(index) * step, y: 0, width: 56, height: height)
            }
        } else {
            grip.frame = CGRect(x: 8, y: 4, width: bounds.width - 16, height: 24)
            let width = bounds.width - 16
            let footerY = bounds.height - footer
            pedestal.frame = CGRect(x: 12, y: footerY + 2, width: bounds.width - 24, height: 1)
            for (index, button) in footerButtons.enumerated() {
                button.frame = CGRect(x: 8, y: footerY + 6 + CGFloat(index) * DesktopToolbarLayout.footerStep, width: width, height: DesktopToolbarLayout.footerButtonHeight)
                button.glyphCenterY = nil
            }
            let top = DesktopToolbarLayout.customInset; let bottom = footerY - DesktopToolbarLayout.customInset
            clip.frame = CGRect(x: 8, y: top, width: width, height: max(1, bottom - top))
            document.frame = CGRect(x: 0, y: -offset, width: width, height: max(contentLength, clip.bounds.height))
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: 0, y: CGFloat(index) * step, width: width, height: height)
            }
        }
        setOffset(offset)
    }
}

@MainActor
final class FloatingSwitcher: NSObject {
    private let panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let sender = ShortcutSender()
    private var history = ApplicationHistory()
    private var preferences = Preferences()
    private var enabled = false
    private var expanded = false
    private var hasPositionedPanel = false
    private var toolbarTransitionTask: Task<Void, Never>?
    private var rebuildAfterTransition = false
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isTransitioning: Bool { toolbarTransitionTask != nil }
    private var preferredCenterY: CGFloat?
    private var preferredCenterX: CGFloat?
    /// Transparent margin around the glass: room for the 14pt soft shadow so the window does not clip it.
    private static let glassPadding: CGFloat = 16
    /// Outside-click region kept at the previous 6pt margin around the bar.
    private var toolbarHitFrame: CGRect { toolbarFrame.insetBy(dx: -6, dy: -6) }
    private var toolbar: ToolbarContent?
    private var buttons: [String: ToolbarButton] = [:]
    private var activePanel: FloatingAction?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var applicationWindowTimer: Timer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    var onAction: (FloatingAction) -> Void = { _ in }
    var onWindowControl: (WindowControl) -> Void = { _ in }
    var onWindowSnap: (WindowSnap) -> Void = { _ in }
    var onArrange: (WindowArrangement) -> Void = { _ in }

    private var scrollOffset: CGFloat = 0
    private static let layoutSize = CGSize(width: 304, height: 288)
    private static var windowPanelSize: CGSize { layoutSize }
    private var windowPanel: NSPanel?
    private func toggleWindowControls(from button: NSView) {
        if windowPanel?.isVisible == true { hideWindowControls(); return }
        guard let window = button.window, let screen = actionScreen else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = DesktopToolbarLayout.flyout(beside: buttonFrame, toolbar: toolbarFrame, in: screen.visibleFrame,
                                                size: Self.windowPanelSize, side: preferences.toolbarSide)
        let flyout = windowPanel ?? ToolbarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        flyout.title = "Better Remote 布局"
        flyout.level = .floating
        flyout.isOpaque = false; flyout.backgroundColor = .clear
        flyout.hasShadow = true; flyout.hidesOnDeactivate = false
        flyout.isReleasedWhenClosed = false
        flyout.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let size = Self.windowPanelSize
        let container = ToolbarDocumentView(frame: CGRect(origin: .zero, size: size))
        let layouts = NSHostingView(rootView: LayoutFlyoutView { [weak self] choice in
            guard let self else { return }
            hideWindowControls()
            switch choice {
            case .snap(let snap): onWindowSnap(snap)
            case .arrange(let arrangement): onArrange(arrangement)
            }
        })
        layouts.frame = CGRect(x: 0, y: 0, width: size.width, height: Self.layoutSize.height)
        container.addSubview(layouts)
        flyout.contentView = NativeGlassView(content: container, cornerRadius: DesignTokens.radiusXl, frame: CGRect(origin: .zero, size: frame.size),
                                             contentBackdrop: DesignTokens.NS.glassBackdrop)
        (flyout.contentView as? NativeGlassView)?.setHairline(DesignTokens.NS.toolbarHairline, omitting: nil)
        flyout.setFrame(frame, display: true)
        flyout.orderFrontRegardless()
        windowPanel = flyout
        updateDismissalMonitors()
    }
    func hideWindowControls() { windowPanel?.orderOut(nil); hideApplicationShortcuts() }
    var onDismissPanels: () -> Void = {}
    var onWillCollapse: () -> Void = {}
    var onExpansionChanged: () -> Void = {}
    var companionFrame: (() -> CGRect?)?

    override init() {
        super.init()
        panel.title = "Better Remote 快捷操作"
        panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sender.targetPID = { [weak self] in self?.targetApplicationPID() }
        sender.onChange = { [weak self] _ in self?.updateSelection() }
    }

    var actionScreen: NSScreen? {
        // A new zero-sized NSPanel can inherit the currently active external display.
        // Anchor explicitly to the system primary display before consulting panel.screen.
        if hasPositionedPanel, let screen = panel.screen { return screen }
        return NSScreen.screens.first ?? NSScreen.main
    }
    var toolbarFrame: CGRect { panel.frame.insetBy(dx: Self.glassPadding, dy: Self.glassPadding) }
    var isExpanded: Bool { enabled && expanded }
    /// Whether the toolbar (collapsed ball or expanded bar) is currently on screen.
    var isVisible: Bool { enabled }
    /// Hidden, ball, or expanded bar: only the expanded bar reserves space from windows.
    var presence: DesktopToolbarLayout.Presence { !enabled ? .hidden : (expanded ? .expanded : .collapsed) }
    var reservedToolbarFrame: CGRect {
        guard let screen = actionScreen else { return panel.frame }
        return DesktopToolbarLayout.toolbar(in: screen.visibleFrame, centerY: preferredCenterY ?? screen.visibleFrame.midY,
                                             expanded: true, count: preferences.enabledOperations.count, side: preferences.toolbarSide, centerX: preferredCenterX, windowControls: preferences.showWindowControls)
    }

    func configure(preferences: Preferences) {
        sender.releaseAll()
        hideApplicationShortcuts()
        self.preferences = preferences
        scrollOffset = 0
        if let activePanel, !FloatingAction.persistentActions.contains(activePanel), !preferences.floatingActions.contains(activePanel) { onDismissPanels() }
        if enabled { rebuild() }
    }
    private weak var toolbarGlass: NativeGlassView?

    func setActivePanel(_ action: FloatingAction?) {
        if action != nil { hideWindowControls() }
        activePanel = action
        updateAttachedSurface()
        updateSelection()
        updateDismissalMonitors()
    }
    private func updateAttachedSurface() {
        let joined = activePanel == .resolution || activePanel == .runningApplications
        if joined { toolbarGlass?.attach(to: preferences.toolbarSide, toolbar: true) }
        else { toolbarGlass?.detach() }
        // Ball and bar draw their own soft layer shadow; the system window shadow adds a hard dark rim
        // on all four edges. The bar gets a 1 px hairline instead, never on the docked edge or a join.
        panel.hasShadow = false
        toolbarShadowHost?.layer?.shadowOpacity = joined ? 0 : DesignTokens.toolbarShadowOpacity
        // Joined: the bar keeps its hairline except on the edge it shares with the panel (the panel draws its own, minus that edge).
        let joinEdge: ToolbarSide = switch preferences.toolbarSide { case .left: .right; case .right: .left; case .top: .bottom; case .bottom: .top }
        toolbarGlass?.setHairline(expanded ? DesignTokens.NS.toolbarSurfaceHairline : nil, omitting: joined ? joinEdge : preferences.toolbarSide)
    }
    private weak var toolbarShadowHost: NSView?
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        if value {
            enabled = true
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                center.addObserver(self, selector: #selector(appChanged(_:)), name: name, object: nil)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            if let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular, app.processIdentifier != ownPID { history.activate(app.processIdentifier) }
            rebuild()
        } else {
            // Hiding an expanded bar frees its space exactly like 收起: let windows reclaim it
            // while the reserved frame is still known (before `enabled`/`expanded` drop).
            if expanded { onWillCollapse() }
            enabled = false
            cancelToolbarTransition()
            applicationWindowTimer?.invalidate(); applicationWindowTimer = nil
            fillTimer?.invalidate(); fillTimer = nil
            applicationWindowScan?.cancel(); applicationWindowScan = nil
            applicationWindowEpoch += 1
            sender.releaseAll(); onDismissPanels()
            panel.orderOut(nil); hideWindowControls()
            hasPositionedPanel = false
            expanded = false
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NotificationCenter.default.removeObserver(self)
            if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            outsideMonitor = nil; localMonitor = nil
        }
        onExpansionChanged()
    }
    /// Shows the full bar (ON in the 桌面工具条 settings), whatever state it was in.
    func showExpanded() {
        setEnabled(true)
        if !expanded { toggleList() }
    }
    func toggleList() {
        guard enabled else { return }
        sender.releaseAll(); onDismissPanels(); hideApplicationShortcuts()
        if expanded { onWillCollapse() }
        expanded.toggle()
        if expanded { scanApplicationWindows() }
        rebuild(animated: true)
        if !isTransitioning { onExpansionChanged() }
    }
    /// Observe outside clicks only while there is actually a popup to dismiss.
    private func updateDismissalMonitors() {
        let needed = enabled && expanded && (activePanel != nil || applicationPanel?.isVisible == true || windowPanel?.isVisible == true)
        if !needed {
            if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            outsideMonitor = nil; localMonitor = nil
            return
        }
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissIfOutside() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissIfOutside() }
            return event
        }
    }

    private func dismissIfOutside() {
        let point = NSEvent.mouseLocation
        if let applicationPanel, applicationPanel.isVisible, !applicationPanel.frame.contains(point), !toolbarHitFrame.contains(point) { hideApplicationShortcuts() }
        if let windowPanel, windowPanel.isVisible, !windowPanel.frame.contains(point), !toolbarHitFrame.contains(point) { hideWindowControls() }
        guard activePanel != nil else { return }
        if !toolbarHitFrame.contains(point), companionFrame?()?.contains(point) != true { onDismissPanels() }
    }
    @objc private func appChanged(_ notification: Notification) {
        if notification.name == NSWorkspace.didActivateApplicationNotification { refreshFillState(after: 0.15) }
        if notification.name == NSWorkspace.didActivateApplicationNotification {
            sender.releaseHeld()
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.activationPolicy == .regular, app.processIdentifier != ownPID {
                history.activate(app.processIdentifier)
                onDismissPanels()
            }
        }
        retainLiveApplications()
        refreshApplicationShortcutTarget()
        scanApplicationWindows()
    }
    /// Cached PIDs with usable windows; refreshed off the main thread.
    private var applicationWindowPIDs: Set<pid_t>?
    private var applicationWindowScan: Task<Void, Never>?
    private var applicationWindowEpoch = 0

    // MARK: 铺满 / 还原 state of the frontmost window

    var fillTargetPID: () -> pid_t? = { nil }
    private var fillTimer: Timer?
    private var fillCheck: Task<Void, Never>?
    private var frontWindowFilled = false
    private func updateFillTimer() {
        let needed = enabled && expanded && preferences.floatingActions.contains(.fillWindow)
        guard needed else { fillTimer?.invalidate(); fillTimer = nil; return }
        guard fillTimer == nil else { refreshFillState(); return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFillState() }
        }
        timer.tolerance = 0.3
        fillTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshFillState()
    }
    func refreshFillState(after delay: TimeInterval = 0) {
        guard delay <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.refreshFillState() }
            }
            return
        }
        guard enabled, expanded, fillCheck == nil, AXIsProcessTrusted(), let pid = fillTargetPID() else { return }
        fillCheck = Task { @MainActor [weak self] in
            let filled = await WindowControlPerformer.frontWindowIsFilled(pid: pid)
            guard let self else { return }
            fillCheck = nil
            frontWindowFilled = filled
            applyFillState()
        }
    }
    private func applyFillState() {
        guard let button = buttons[ConfiguredOperation.builtin(.fillWindow).id] else { return }
        if frontWindowFilled {
            button.update(symbol: FloatingAction.restoreFillSymbol, name: FloatingAction.restoreFillTitle)
        } else {
            button.update(symbol: preferences.floatingActionIcons[FloatingAction.fillWindow.rawValue] ?? FloatingAction.fillWindow.symbol,
                          name: FloatingAction.fillWindow.title)
        }
    }

    private func updateApplicationWindowTimer() {
        updateFillTimer()
        let needed = enabled && expanded && preferences.applicationShortcutsEnabled && !preferences.applicationShortcuts.isEmpty
        guard needed else {
            applicationWindowTimer?.invalidate(); applicationWindowTimer = nil
            return
        }
        guard applicationWindowTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanApplicationWindows() }
        }
        timer.tolerance = 0.3
        applicationWindowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        scanApplicationWindows()
    }

    private func scanApplicationWindows() {
        guard enabled, expanded, preferences.applicationShortcutsEnabled, !preferences.applicationShortcuts.isEmpty, applicationWindowScan == nil else { return }
        let epoch = applicationWindowEpoch
        applicationWindowScan = Task { @MainActor [weak self] in
            let pids = Set(await ApplicationWindowCatalog.shared.snapshot().map(\.pid))
            guard let self, epoch == applicationWindowEpoch else { return }
            applicationWindowScan = nil
            guard self.enabled, self.expanded, !Task.isCancelled else { return }
            guard pids != applicationWindowPIDs else { return }
            applicationWindowPIDs = pids
            refreshApplicationShortcutTarget()
        }
    }
    private func refreshApplicationShortcutTarget() {
        let next = shortcutApplication?.processIdentifier
        if displayedApplicationPID != next {
            OperationDiagnostics.write("application-shortcut-target front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) previous=\(displayedApplicationPID ?? 0) next=\(next ?? 0)")
            sender.releaseAll()
            hideApplicationShortcuts()
            if enabled { rebuild() }
        }
    }
    @objc private func screenChanged() {
        guard enabled else { return }
        sender.releaseAll(); onDismissPanels()
        redock()
    }
    private var redockGeneration = 0
    /// Re-dock to the saved edge after a display change. The screen-parameters
    /// notification can arrive before NSScreen reports the new frame, so lay out
    /// now and again once the display mode has settled.
    func redock() {
        let interrupted = isTransitioning
        cancelToolbarTransition()
        guard enabled else { return }
        redockGeneration += 1
        let generation = redockGeneration
        let relayout = { [weak self] in
            guard let self, self.enabled, generation == self.redockGeneration else { return }
            self.hasPositionedPanel = false
            self.rebuild()
        }
        relayout()
        if interrupted { onExpansionChanged() }
        for delay in [0.35, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { relayout() } }
        }
    }
    private func retainLiveApplications() {
        history.retain(Set(NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != ownPID }.map(\.processIdentifier)))
    }
    func targetApplicationPID() -> pid_t? {
        retainLiveApplications()
        let windows = ApplicationWindowCatalog.shared.visibleWindows()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let usable = front.flatMap { $0 == ownPID ? nil : ApplicationWindowCatalog.shared.focusedWindowUsable(pid: $0) }
        let target = ApplicationTargetPolicy.resolve(frontmost: front, ownPID: ownPID,
                                                     visibleWindowPIDs: windows.map(\.pid), recent: history.recent,
                                                     frontmostWindowUsable: usable)
        if target != front {
            OperationDiagnostics.write("target-fallback front=\(front ?? 0) focusedUsable=\(String(describing: usable)) target=\(target ?? 0)")
        }
        return target
    }
    private func rebuild(animated: Bool = false) {
        if !animated, isTransitioning {
            rebuildAfterTransition = true
            return
        }
        cancelToolbarTransition()
        updateApplicationWindowTimer()
        guard let screen = actionScreen else { return }
        let visible = screen.visibleFrame
        let application = shortcutApplication
        displayedApplicationPID = application?.processIdentifier
        let center = preferredCenterY ?? visible.midY
        let grid = DesktopToolbarLayout.grid(in: visible, count: preferences.enabledOperations.count, side: preferences.toolbarSide, windowControls: preferences.showWindowControls)
        let frame = DesktopToolbarLayout.toolbar(in: visible, centerY: center, expanded: expanded, count: preferences.enabledOperations.count, side: preferences.toolbarSide, centerX: preferredCenterX, windowControls: preferences.showWindowControls)
        let windowFrame = frame.insetBy(dx: -Self.glassPadding, dy: -Self.glassPadding)
        buttons.removeAll()
        if expanded {
            let content = ToolbarContent(frame: CGRect(origin: .zero, size: frame.size), grid: grid, side: preferences.toolbarSide, application: application)
            content.applicationButton?.onTap = { [weak self, weak content] in
                guard let self, let button = content?.applicationButton else { return }
                toggleApplicationShortcuts(from: button)
            }
            content.grip.isHidden = true
            content.collapse.onTap = { [weak self] in self?.toggleList() }
            content.resolution.onTap = { [weak self] in self?.performPersistent(.resolution) }
            buttons[ConfiguredOperation.builtin(.resolution).id] = content.resolution
            content.settings.onTap = { [weak self] in self?.performPersistent(.settings) }
            content.restore.onTap = { [weak self] in self?.performPersistent(.restoreDisplay) }
            hideWindowControls()
            content.windowButton?.onTap = { [weak self, weak content] in
                guard let self, let button = content?.windowButton else { return }
                sender.releaseAll(); onDismissPanels()
                toggleWindowControls(from: button)
            }
            content.onOffsetChange = { [weak self] in self?.scrollOffset = $0 }
            for operation in preferences.enabledOperations {
                let button: ToolbarButton
                switch operation {
                case .shortcut(let shortcut):
                    button = ToolbarButton(symbol: shortcut.icon.rawValue, name: shortcut.name)
                    if shortcut.mode == .press, ShortcutEventPlan.mask(for: shortcut.key.code) == nil {
                        // Finish the remote mouse gesture before sending a
                        // complete key press; a click must not hold modifiers.
                        button.onTap = { [weak self] in
                            guard let self else { return }
                            hideApplicationShortcuts()
                            onDismissPanels()
                            sender.enqueueTap(shortcut)
                        }
                    } else {
                        button.onPress = { [weak self] in
                            guard let self else { return }
                            hideApplicationShortcuts()
                            onDismissPanels()
                            do { try sender.press(shortcut) }
                            catch { NSSound.beep() }
                        }
                        button.onRelease = { [weak self] in self?.sender.release(shortcut) }
                    }
                case .builtin(let action):
                    button = ToolbarButton(symbol: preferences.floatingActionIcons[action.rawValue] ?? action.symbol, name: action.title)
                    if let hint = action.hint { button.toolTip = hint }
                    button.onTap = { [weak self] in
                        guard let self else { return }
                        hideApplicationShortcuts()
                        sender.releaseAll()
                        if action != .runningApplications && action != .resolution { onDismissPanels() }
                        onAction(action)
                    }
                }
                button.identifier = .init(operation.id)
                button.dragsHorizontally = preferences.toolbarSide.isHorizontal
                button.onScrollDrag = { [weak content] delta in
                    guard let content else { return }
                    content.setOffset(content.offset + delta)
                }
                content.buttons.append(button)
                content.document.addSubview(button)
                buttons[operation.id] = button
                if operation.id == ConfiguredOperation.builtin(.fillWindow).id, frontWindowFilled {
                    button.update(symbol: FloatingAction.restoreFillSymbol, name: FloatingAction.restoreFillTitle)
                }
            }
            toolbar = content
            content.layoutSubtreeIfNeeded()
            content.setOffset(scrollOffset)
            panel.contentView = paddedGlass(content: content, cornerRadius: DesignTokens.radiusXl, improvesContrast: true)
        } else {
            toolbar = nil
            let handle = ToolbarButton(symbol: "macbook.and.iphone", name: "展开快捷操作", showsCaption: false, largeIcon: true)
            handle.isCircular = true
            handle.frame = CGRect(origin: .zero, size: frame.size)
            handle.onTap = { [weak self] in self?.toggleList() }
            handle.dragsHorizontally = false
            handle.onDrag = { [weak self] origin in self?.move(to: origin) }
            panel.contentView = paddedGlass(content: handle, cornerRadius: frame.width / 2)
        }
        updateSelection()
        if animated && !reduceMotion() {
            animateToolbar(to: windowFrame)
            if let toolbar, expanded {
                let controls = toolbar.buttons + [toolbar.windowButton, toolbar.applicationButton, toolbar.resolution, toolbar.settings, toolbar.collapse].compactMap { $0 }
                for (index, button) in controls.enumerated() where !button.isHidden {
                    button.animateEntrance(delay: min(Double(index) * 0.024, 0.096), side: preferences.toolbarSide)
                }
            }
        } else {
            panel.setFrame(windowFrame, display: true)
        }
        hasPositionedPanel = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }

    private func cancelToolbarTransition() {
        toolbarTransitionTask?.cancel()
        toolbarTransitionTask = nil
        rebuildAfterTransition = false
    }

    private func animateToolbar(to target: CGRect) {
        let start = panel.frame
        let duration = expanded ? 0.34 : 0.18
        let started = ProcessInfo.processInfo.systemUptime
        let opening = expanded
        toolbarTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let progress = min((ProcessInfo.processInfo.systemUptime - started) / duration, 1)
                let value: Double
                if opening {
                    let t = progress - 1
                    value = 1 + 2.05 * t * t * t + 1.05 * t * t
                } else { value = progress * progress }
                func interpolate(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * value }
                panel.setFrame(CGRect(x: interpolate(start.minX, target.minX), y: interpolate(start.minY, target.minY),
                                     width: interpolate(start.width, target.width), height: interpolate(start.height, target.height)), display: true)
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
            toolbarTransitionTask = nil
            if rebuildAfterTransition { rebuildAfterTransition = false; rebuild() }
            onExpansionChanged()
        }
    }
    private var applicationPanel: NSPanel?
    private var displayedApplicationPID: pid_t?
    private var shortcutApplication: NSRunningApplication? {
        guard preferences.applicationShortcutsEnabled, !preferences.applicationShortcuts.isEmpty else { return nil }
        let front = NSWorkspace.shared.frontmostApplication
        let live = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        guard let pid = ApplicationShortcutTarget.resolve(frontmost: front?.processIdentifier, ownPID: ownPID,
                                                          frontmostIsRegular: front?.activationPolicy == .regular,
                                                          recent: history.recent,
                                                          liveRegularPIDs: Set(live.map(\.processIdentifier)),
                                                          visibleWindowPIDs: applicationWindowPIDs ?? []),
              let app = live.first(where: { $0.processIdentifier == pid }),
              preferences.applicationShortcuts(for: app.bundleIdentifier) != nil else { return nil }
        return app
    }

    private func hideApplicationShortcuts() {
        applicationPanel?.orderOut(nil)
        toolbar?.applicationButton?.selected = false
        updateDismissalMonitors()
    }
    private func toggleApplicationShortcuts(from button: NSView) {
        if applicationPanel?.isVisible == true { hideApplicationShortcuts(); return }
        guard let app = shortcutApplication, let group = preferences.applicationShortcuts(for: app.bundleIdentifier),
              let window = button.window, let screen = actionScreen else { return }
        sender.releaseAll()
        onDismissPanels()
        hideWindowControls()
        let shortcuts = group.enabledShortcuts
        let available = DesktopToolbarLayout.workspace(avoiding: toolbarFrame, in: screen.visibleFrame, side: preferences.toolbarSide)
        let cellWidth = DesktopToolbarLayout.width - 16
        let cellHeight = DesktopToolbarLayout.buttonHeight
        let step = DesktopToolbarLayout.step
        let columns = min(shortcuts.count, min(3, max(1, Int((available.width - 16 + 8) / step))))
        let rows = Int(ceil(Double(shortcuts.count) / Double(columns)))
        let contentHeight = CGFloat(rows - 1) * step + cellHeight + 16
        let size = CGSize(width: CGFloat(columns - 1) * step + cellWidth + 16,
                          height: min(contentHeight, max(cellHeight + 16, available.height - 16)))
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = DesktopToolbarLayout.flyout(beside: buttonFrame, toolbar: toolbarFrame, in: screen.visibleFrame,
                                                size: size, side: preferences.toolbarSide)
        let flyout = ToolbarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        flyout.title = "Better Remote 应用快捷操作"
        flyout.level = .floating
        flyout.isOpaque = false; flyout.backgroundColor = .clear
        flyout.hasShadow = true; flyout.hidesOnDeactivate = false
        flyout.isReleasedWhenClosed = false
        flyout.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Exactly the 窗口 panel structure: plain flipped container + SwiftUI content
        // inside NativeGlassView. (An NSScrollView as the glass content picked up the
        // glass backdrop layer and masked corners, rendering as an opaque gray card with a rim.)
        let container = ToolbarDocumentView(frame: CGRect(origin: .zero, size: frame.size))
        let items = NSHostingView(rootView: ApplicationShortcutFlyoutView(
            items: shortcuts.map { ($0.icon.rawValue, $0.name) }, columns: columns,
            tile: CGSize(width: cellWidth, height: cellHeight), spacing: step - cellWidth,
            scrolls: contentHeight > frame.height) { [weak self] index in
                guard let self, shortcutApplication?.processIdentifier == app.processIdentifier, shortcuts.indices.contains(index) else { return }
                // Keep the flyout open for repeated shortcuts; outside clicks dismiss it.
                sender.enqueueTap(shortcuts[index], targetPID: app.processIdentifier)
            })
        items.sizingOptions = []
        items.frame = container.bounds
        container.addSubview(items)
        flyout.contentView = NativeGlassView(content: container, cornerRadius: DesignTokens.radiusXl, frame: CGRect(origin: .zero, size: frame.size),
                                             contentBackdrop: DesignTokens.NS.glassBackdrop)
        (flyout.contentView as? NativeGlassView)?.setHairline(DesignTokens.NS.toolbarHairline, omitting: nil)
        flyout.setFrame(frame, display: true)
        flyout.invalidateShadow()
        applicationPanel = flyout
        flyout.orderFrontRegardless()
        toolbar?.applicationButton?.selected = true
        updateDismissalMonitors()
    }

    private func performPersistent(_ action: FloatingAction) {
        hideApplicationShortcuts()
        sender.releaseAll()
        if action != .resolution { onDismissPanels() }
        onAction(action)
    }
    /// Expanded bar as built by `rebuild`, without a panel, for offscreen review renders only.
    /// `hairline: false` reproduces the previous edge treatment minus the window-server rim (not capturable offscreen).
    static func reviewToolbar(preferences: Preferences, in visible: CGRect, hairline: Bool, backdrop: NSColor = DesignTokens.NS.toolbarSurfaceBackdrop) -> NSView {
        let side = preferences.toolbarSide
        let count = preferences.enabledOperations.count
        let grid = DesktopToolbarLayout.grid(in: visible, count: count, side: side, windowControls: preferences.showWindowControls)
        let frame = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: true, count: count, side: side, windowControls: preferences.showWindowControls)
        let content = ToolbarContent(frame: CGRect(origin: .zero, size: frame.size), grid: grid, side: side)
        content.grip.isHidden = true
        for operation in preferences.enabledOperations {
            let button: ToolbarButton
            switch operation {
            case .shortcut(let shortcut): button = ToolbarButton(symbol: shortcut.icon.rawValue, name: shortcut.name)
            case .builtin(let action):
                button = ToolbarButton(symbol: preferences.floatingActionIcons[action.rawValue] ?? action.symbol, name: action.title)
                if let hint = action.hint { button.toolTip = hint }
            }
            content.buttons.append(button)
            content.document.addSubview(button)
        }
        content.layoutSubtreeIfNeeded()
        let padding = glassPadding
        let container = NSView(frame: CGRect(origin: .zero, size: content.bounds.insetBy(dx: -padding, dy: -padding).size))
        // System glass and behind-window blur cannot be captured offscreen (they render as an opaque
        // fallback), so the review surface is the tint layer the glass carries, plus the hairline.
        let surface = NSView(frame: CGRect(origin: CGPoint(x: padding, y: padding), size: content.bounds.size))
        surface.wantsLayer = true
        surface.layer?.cornerRadius = DesignTokens.radiusXl
        surface.layer?.masksToBounds = true
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { surface.layer?.backgroundColor = backdrop.cgColor }
        surface.addSubview(content)
        container.addSubview(surface)
        if hairline {
            let edge = HairlineEdgeView(frame: surface.frame)
            edge.color = DesignTokens.NS.toolbarSurfaceHairline
            edge.omitted = side
            edge.cornerRadius = DesignTokens.radiusXl
            container.addSubview(edge)
        }
        return container
    }
    /// The window-layout flyout for offscreen renders: same content and size as the live flyout, on a tint surface.
    static func reviewLayoutFlyout(backdrop: NSColor = DesignTokens.NS.glassBackdrop) -> NSView {
        let size = windowPanelSize
        let layouts = NSHostingView(rootView: LayoutFlyoutView { _ in })
        layouts.frame = CGRect(x: 0, y: 0, width: size.width, height: layoutSize.height)
        let surface = NSView(frame: CGRect(origin: .zero, size: layouts.frame.size))
        surface.wantsLayer = true
        surface.layer?.cornerRadius = DesignTokens.radiusXl
        surface.layer?.masksToBounds = true
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { surface.layer?.backgroundColor = backdrop.cgColor }
        surface.addSubview(layouts)
        let edge = HairlineEdgeView(frame: surface.bounds)
        edge.color = DesignTokens.NS.toolbarHairline
        edge.cornerRadius = DesignTokens.radiusXl
        surface.addSubview(edge)
        return surface
    }
    /// The expanded bar with the window-layout flyout open beside its 布局 button, placed exactly as the live
    /// flyout is (`DesktopToolbarLayout.flyout`: one margin from the bar, centred on the button), for offscreen renders.
    static func reviewToolbarWithLayoutFlyout(preferences: Preferences, in visible: CGRect, backdrop: NSColor = DesignTokens.NS.glassBackdrop) -> NSView {
        let bar = reviewToolbar(preferences: preferences, in: visible, hairline: true, backdrop: backdrop)
        let flyout = reviewLayoutFlyout(backdrop: backdrop)
        func find(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "persistent:window" { return view }
            for sub in view.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        let gap = DesktopToolbarLayout.margin
        let canvas = NSView(frame: CGRect(x: 0, y: 0, width: flyout.frame.width + gap + bar.frame.width, height: bar.frame.height))
        bar.frame.origin = CGPoint(x: canvas.bounds.width - bar.frame.width, y: 0)
        canvas.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        let screen = canvas.bounds.insetBy(dx: 0, dy: gap)
        let button = find(bar).map { $0.convert($0.bounds, to: canvas) } ?? CGRect(x: bar.frame.minX, y: canvas.bounds.midY, width: 1, height: 1)
        let frame = DesktopToolbarLayout.flyout(beside: button, toolbar: bar.frame, in: screen.union(CGRect(x: 0, y: screen.minY, width: 1, height: 1)),
                                                size: flyout.frame.size, side: .right)
        flyout.frame = CGRect(x: 0, y: frame.minY, width: flyout.frame.width, height: flyout.frame.height)
        canvas.addSubview(flyout)
        return canvas
    }
    private func paddedGlass(content: NSView, cornerRadius: CGFloat, improvesContrast: Bool = false) -> NSView {
        let padding = Self.glassPadding
        let container = NSView(frame: content.bounds.insetBy(dx: -padding, dy: -padding))
        container.setFrameOrigin(.zero)
        let glass = NativeGlassView(content: content, cornerRadius: cornerRadius,
                                    frame: CGRect(origin: CGPoint(x: padding, y: padding), size: content.bounds.size),
                                    contentBackdrop: improvesContrast ? DesignTokens.NS.toolbarSurfaceBackdrop : nil,
                                    lightBlurAlpha: DesignTokens.NS.toolbarLightBlurAlpha)
        toolbarGlass = glass
        glass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glass)
        let glassRect = CGRect(origin: CGPoint(x: padding, y: padding), size: content.bounds.size)
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = DesignTokens.toolbarShadowOpacity
        container.layer?.shadowRadius = DesignTokens.toolbarShadowRadius
        container.layer?.shadowOffset = CGSize(width: 0, height: DesignTokens.toolbarShadowOffsetY)
        container.layer?.shadowPath = expanded
            ? CGPath(roundedRect: glassRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            : CGPath(ellipseIn: glassRect, transform: nil)
        toolbarShadowHost = container
        updateAttachedSurface()
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            glass.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding)
        ])
        return container
    }

    private func move(to origin: CGPoint) {
        guard let screen = actionScreen else { return }
        if activePanel != nil { onDismissPanels() }
        let visible = screen.visibleFrame
        if !expanded {
            let collapsed = DesktopToolbarLayout.toolbar(in: visible, centerY: visible.midY, expanded: false, count: 0)
            let minY = visible.minY + DesktopToolbarLayout.margin - Self.glassPadding
            let maxY = visible.maxY - panel.frame.height - DesktopToolbarLayout.margin + Self.glassPadding
            panel.setFrameOrigin(CGPoint(x: collapsed.minX - Self.glassPadding, y: min(max(origin.y, minY), max(minY, maxY))))
            return
        }
        let horizontal = preferences.toolbarSide.isHorizontal
        var target = horizontal ? origin.x + panel.frame.width / 2 : origin.y + panel.frame.height / 2
        let lower = horizontal ? visible.minX : visible.minY
        let length = horizontal ? visible.width : visible.height
        for fraction: CGFloat in [0.5, 0.75, 0.25] {
            let snap = lower + length * fraction
            if abs(target - snap) < (fraction == 0.5 ? 28 : 24) { target = snap; break }
        }
        if horizontal { preferredCenterX = target } else { preferredCenterY = target }
        let frame = DesktopToolbarLayout.toolbar(in: visible, centerY: preferredCenterY ?? visible.midY,
                                                expanded: expanded, count: preferences.enabledOperations.count,
                                                side: preferences.toolbarSide, centerX: preferredCenterX, windowControls: preferences.showWindowControls)
        panel.setFrameOrigin(CGPoint(x: frame.minX - Self.glassPadding, y: frame.minY - Self.glassPadding))
    }
    private func updateSelection() {
        for (id, button) in buttons {
            let held = sender.heldID.map { ConfiguredOperation.shortcutID($0) == id } ?? false
            let selected = activePanel.map { ConfiguredOperation.builtin($0).id == id } ?? false
            button.selected = held || selected
        }
    }
}
