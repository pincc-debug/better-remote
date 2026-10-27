import AppKit
import SwiftUI
import RemoteFitCore

/// Native tracking works in the nonactivating launcher without starting a drag or menu.
struct LauncherPressTarget: NSViewRepresentable {
    let name: String
    let enabled: Bool
    let onTap: () -> Void
    let onPreview: () -> Void
    let onHighlight: (Bool) -> Void

    func makeNSView(context: Context) -> LauncherPressButton { LauncherPressButton() }

    func updateNSView(_ view: LauncherPressButton, context: Context) {
        view.setAccessibilityLabel(name)
        view.toolTip = name
        view.isEnabled = enabled
        view.onTap = onTap
        view.onPreview = onPreview
        view.onHighlight = onHighlight
    }
}

final class LauncherPressButton: NSButton {
    var onTap: () -> Void = {}
    var onPreview: () -> Void = {}
    var onHighlight: (Bool) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(activate)
        setAccessibilityRole(.button)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "显示名称", target: self, selector: #selector(showName))])
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {}
    @objc private func showName() -> Bool {
        guard isEnabled else { return false }
        onPreview()
        return true
    }
    @objc private func activate() { if isEnabled { onTap() } }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onTap()
        return true
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let trackingWindow = window else { return }
        let started = Date()
        let origin = NSEvent.mouseLocation
        var press = ApplicationPress()
        var last = origin
        var scrolling = false
        onHighlight(true)
        defer { onHighlight(false) }
        while trackingWindow.isVisible {
            let deadline = press.previewed || press.cancelled
                ? Date(timeIntervalSinceNow: 0.1)
                : min(started.addingTimeInterval(ApplicationPress.previewDelay), Date(timeIntervalSinceNow: 0.1))
            let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: deadline, inMode: .eventTracking, dequeue: true)
            let pointer = NSEvent.mouseLocation
            let inside = bounds.contains(convert(trackingWindow.convertPoint(fromScreen: pointer), from: nil))
            if !press.previewed, !scrolling, hypot(pointer.x - origin.x, pointer.y - origin.y) > 6 {
                scrolling = true
                onHighlight(false)
            }
            if scrolling { scrollEnclosing(by: pointer.y - last.y) }
            last = pointer
            if press.update(elapsed: Date().timeIntervalSince(started), distance: hypot(pointer.x - origin.x, pointer.y - origin.y), inside: inside) {
                onPreview()
            }
            if next?.type == .leftMouseUp {
                if !scrolling, press.shouldLaunch(inside: inside) { onTap() }
                return
            }
            if NSEvent.pressedMouseButtons & 1 == 0 { return }
            if press.cancelled { onHighlight(false) }
        }
    }

    /// A finger drag that starts on an icon scrolls the list instead of launching.
    private func scrollEnclosing(by delta: CGFloat) {
        guard delta != 0, let scrollView = enclosingScrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.y += document.isFlipped ? delta : -delta
        origin.y = min(max(0, origin.y), max(0, document.frame.height - clip.bounds.height))
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
