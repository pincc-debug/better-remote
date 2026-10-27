import AppKit
import SwiftUI
import RemoteFitCore

/// Content lives inside the system glass view so refraction and legibility are
/// handled by AppKit. Older systems use an active behind-window blur.
@MainActor
final class NativeGlassView: NSView {
    private let surface: NSView
    private let lightBlur: NSVisualEffectView?
    private let embedded: NSView
    private let cornerRadius: CGFloat
    private let contentBackdrop: NSColor?
    private let clear: Bool
    private var contentConstraints: [NSLayoutConstraint] = []

    init(content: NSView, cornerRadius: CGFloat, frame: NSRect = .zero, clear: Bool = false, contentBackdrop: NSColor? = nil) {
        embedded = content
        self.cornerRadius = cornerRadius
        self.contentBackdrop = contentBackdrop
        self.clear = clear
        if let contentBackdrop {
            content.wantsLayer = true
            content.layer?.backgroundColor = contentBackdrop.cgColor
            content.layer?.cornerRadius = cornerRadius
            content.layer?.masksToBounds = true
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = clear ? .clear : .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = nil
            glass.contentView = content
            if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(true, forKey: "effectIsInteractive")
            }
            surface = glass
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .sidebar
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = cornerRadius
            blur.layer?.masksToBounds = true
            lightBlur = blur
        } else {
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = cornerRadius
            blur.layer?.masksToBounds = true
            blur.layer?.borderWidth = 0
            blur.addSubview(content)
            surface = blur
            lightBlur = nil
        }
        super.init(frame: frame)
        wantsLayer = false
        addSubview(surface)
        pin(surface, to: self)
        if let lightBlur {
            addSubview(lightBlur, positioned: .below, relativeTo: surface)
            pin(lightBlur, to: self)
        }
        if let container = content.superview {
            contentConstraints = pin(content, to: container)
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { return nil }

    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView, let lightBlur {
            if isDark, glass.contentView !== embedded {
                NSLayoutConstraint.deactivate(contentConstraints)
                embedded.removeFromSuperview()
                glass.contentView = embedded
                if let container = embedded.superview { contentConstraints = pin(embedded, to: container) }
            } else if !isDark, embedded.superview !== lightBlur {
                NSLayoutConstraint.deactivate(contentConstraints)
                glass.contentView = nil
                embedded.removeFromSuperview()
                lightBlur.addSubview(embedded)
                contentConstraints = pin(embedded, to: lightBlur)
            }
            surface.isHidden = !isDark
            lightBlur.isHidden = isDark
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            embedded.layer?.backgroundColor = contentBackdrop?.cgColor
        }
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.style = clear ? .clear : .regular
        } else if let blur = surface as? NSVisualEffectView {
            blur.material = isDark ? .hudWindow : .popover
        }
        needsDisplay = true
    }

    private var attachedCorners: CACornerMask?
    private var hairline: HairlineEdgeView?

    /// A 1 px edge drawn by us (instead of the window server's shadow rim), skipping `omitting`'s edge.
    func setHairline(_ color: NSColor?, omitting side: ToolbarSide?) {
        guard let color else { hairline?.removeFromSuperview(); hairline = nil; return }
        let view = hairline ?? HairlineEdgeView(frame: bounds)
        view.color = color
        view.omitted = side
        view.cornerRadius = attachedCorners == nil ? cornerRadius : 0
        if hairline == nil {
            addSubview(view, positioned: .above, relativeTo: surface)
            pin(view, to: self)
            hairline = view
        }
        view.needsDisplay = true
    }

    func attach(to side: ToolbarSide, toolbar: Bool = false) {
        let bottomLeft: CACornerMask = .layerMinXMinYCorner
        let bottomRight: CACornerMask = .layerMaxXMinYCorner
        let topLeft: CACornerMask = .layerMinXMaxYCorner
        let topRight: CACornerMask = .layerMaxXMaxYCorner
        switch (side, toolbar) {
        case (.right, false), (.left, true): attachedCorners = [topLeft, bottomLeft]
        case (.left, false), (.right, true): attachedCorners = [topRight, bottomRight]
        case (.top, false): attachedCorners = [bottomLeft, bottomRight]
        case (.bottom, false): attachedCorners = [topLeft, topRight]
        case (.top, true): attachedCorners = [topLeft, topRight, bottomRight]
        case (.bottom, true): attachedCorners = [bottomLeft, bottomRight, topRight]
        }
        updateShape()
    }

    func detach() {
        attachedCorners = nil
        updateShape()
    }

    private func updateShape() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.maskedCorners = attachedCorners ?? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
        embedded.layer?.cornerRadius = attachedCorners == nil ? cornerRadius : 0
        needsLayout = true
    }

    func reveal(from side: ToolbarSide) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layoutSubtreeIfNeeded()
        let mask = CAShapeLayer()
        let full = bounds
        var start = full
        if side.isHorizontal {
            start.size.height = 1
            if side == .top { start.origin.y = full.maxY - 1 }
        } else {
            start.size.width = 1
            if side == .right { start.origin.x = full.maxX - 1 }
        }
        mask.path = CGPath(rect: full, transform: nil)
        layer?.mask = mask
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = CGPath(rect: start, transform: nil)
        animation.toValue = mask.path
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak mask] in
            MainActor.assumeIsolated {
                if self?.layer?.mask === mask { self?.layer?.mask = nil }
            }
        }
        mask.add(animation, forKey: "unfold")
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        hairline?.cornerRadius = attachedCorners == nil ? cornerRadius : 0
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = attachedCorners == nil ? cornerRadius : 0
        } else {
            surface.layer?.cornerRadius = attachedCorners == nil ? cornerRadius : 0
        }
        lightBlur?.layer?.cornerRadius = attachedCorners == nil ? cornerRadius : 0
    }

    @discardableResult
    private func pin(_ child: NSView, to parent: NSView) -> [NSLayoutConstraint] {
        child.translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    func applyTint(_ color: NSColor?) {
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.tintColor = color
        }
    }
}

/// Non-interactive overlay that strokes the glass outline with a one-physical-pixel line.
@MainActor
final class HairlineEdgeView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    var omitted: ToolbarSide? { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { if oldValue != cornerRadius { needsDisplay = true } } }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsDisplay = true }
    var lineWidth: CGFloat { DesignTokens.hairline(scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) }
    /// Visible region for the stroke: everything except a strip along the docked edge.
    static func clip(_ bounds: CGRect, omitting side: ToolbarSide?, lineWidth: CGFloat) -> CGRect {
        guard let side else { return bounds }
        var rect = bounds
        switch side {
        case .left: rect.origin.x += lineWidth; rect.size.width -= lineWidth
        case .right: rect.size.width -= lineWidth
        case .bottom: rect.origin.y += lineWidth; rect.size.height -= lineWidth
        case .top: rect.size.height -= lineWidth
        }
        return rect
    }
    override func draw(_ dirtyRect: NSRect) {
        let width = lineWidth
        let rect = bounds.insetBy(dx: width / 2, dy: width / 2)
        let radius = max(0, cornerRadius - width / 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: Self.clip(bounds, omitting: omitted, lineWidth: width)).addClip()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = width
        effectiveAppearance.performAsCurrentDrawingAppearance { color.setStroke() }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
private final class InteractiveGlassHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
}

@MainActor
func glassHost<Content: View>(_ content: Content, cornerRadius: CGFloat = 24) -> NSView {
    filledHost(content, background: .clear, cornerRadius: cornerRadius)
}

@MainActor
func solidHost<Content: View>(_ content: Content) -> NSView {
    let host = InteractiveGlassHostingView(rootView: content)
    host.sizingOptions = []
    host.setContentHuggingPriority(.defaultLow, for: .horizontal)
    host.setContentHuggingPriority(.defaultLow, for: .vertical)
    host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    host.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return host
}

@MainActor
private func filledHost<Content: View>(_ content: Content, background: NSColor, cornerRadius: CGFloat?) -> NSView {
    let host = InteractiveGlassHostingView(rootView: content)
    host.wantsLayer = true
    host.layer?.backgroundColor = background.cgColor
    host.sizingOptions = []
    host.setContentHuggingPriority(.defaultLow, for: .horizontal)
    host.setContentHuggingPriority(.defaultLow, for: .vertical)
    host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    host.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    guard let cornerRadius else { return host }
    return NativeGlassView(content: host, cornerRadius: cornerRadius, contentBackdrop: DesignTokens.NS.glassBackdrop)
}
