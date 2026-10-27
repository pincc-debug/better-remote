import AppKit
import RemoteFitCore

/// Lets a one-finger swipe (remote touch = click-drag) scroll the Settings window's scroll views,
/// like the toolbar and panels already do. Taps stay clicks: nothing changes until the drag passes
/// `DragScrollGesture.threshold`, and a drag that became a scroll releases outside the window so
/// the control under the finger cancels instead of firing.
@MainActor
final class WindowDragScroll {
    private weak var window: NSWindow?
    nonisolated(unsafe) private var monitor: Any?
    private var gesture: DragScrollGesture?
    private weak var scrollView: NSScrollView?

    init(window: NSWindow) {
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            nonisolated(unsafe) let input = event
            nonisolated(unsafe) var output: NSEvent? = event
            MainActor.assumeIsolated { output = self?.handle(input) ?? input }
            return output
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown:
            gesture = nil; scrollView = nil
            guard let hit = window.contentView?.hitTest(event.locationInWindow), !Self.isExcluded(hit),
                  let scroll = Self.scrollView(containing: hit), let document = scroll.documentView,
                  document.frame.height > scroll.contentView.bounds.height + 1 else { return event }
            scrollView = scroll
            gesture = DragScrollGesture(start: event.locationInWindow, startOffset: Self.offset(of: scroll))
            return event
        case .leftMouseDragged:
            guard var g = gesture, let scroll = scrollView, let document = scroll.documentView else { return event }
            let maxOffset = document.frame.height - scroll.contentView.bounds.height
            guard let offset = g.drag(to: event.locationInWindow, maxOffset: maxOffset) else { gesture = g; return event }
            gesture = g
            Self.setOffset(offset, of: scroll)
            return nil
        case .leftMouseUp:
            defer { gesture = nil; scrollView = nil }
            guard gesture?.isScrolling == true else { return event }
            // Release far outside so the pressed control cancels rather than clicks.
            return NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: -10_000, y: -10_000), modifierFlags: event.modifierFlags,
                                      timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                      eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: 0) ?? event
        default: return event
        }
    }

    private static func scrollView(containing view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let scroll = v as? NSScrollView, scroll.hasVerticalScroller || scroll.documentView != nil { return scroll }
            current = v.superview
        }
        return nil
    }
    /// Text editing, sliders and reorder handles keep their own drag behaviour.
    private static func isExcluded(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v is NSTextView || v is NSSlider || (v as? NSTextField)?.isEditable == true || v is OperationDragHandleMarker { return true }
            current = v.superview
        }
        return false
    }
    private static func offset(of scroll: NSScrollView) -> CGFloat {
        let clip = scroll.contentView, document = scroll.documentView
        if document?.isFlipped ?? true { return clip.bounds.origin.y }
        return (document?.frame.height ?? 0) - clip.bounds.height - clip.bounds.origin.y
    }
    private static func setOffset(_ offset: CGFloat, of scroll: NSScrollView) {
        let clip = scroll.contentView
        let flipped = scroll.documentView?.isFlipped ?? true
        let height = scroll.documentView?.frame.height ?? 0
        let y = flipped ? offset : height - clip.bounds.height - offset
        clip.scroll(to: CGPoint(x: clip.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(clip)
    }
}

/// Views that own vertical drags themselves (operation reordering) adopt this.
protocol OperationDragHandleMarker {}
