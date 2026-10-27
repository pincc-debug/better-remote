import AppKit
import SwiftUI

struct OperationDragHandle: NSViewRepresentable {
    let id: String
    let title: String
    let cardSize: CGSize
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> OperationDragHandleView { OperationDragHandleView() }
    func updateNSView(_ view: OperationDragHandleView, context: Context) {
        view.operationID = id
        view.cardSize = cardSize
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.toolTip = "拖动排序"
        view.setAccessibilityLabel("排序\(title)")
    }
}

/// A transparent drag surface lets the entire shortcut pill own the gesture,
/// including in settings windows that otherwise turn click-drags into scrolling.
struct OperationDragSurface: NSViewRepresentable {
    let id: String
    let onTap: () -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> OperationDragHandleView {
        let view = OperationDragHandleView()
        view.coversCard = true
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: OperationDragHandleView, context: Context) {
        view.operationID = id
        view.onTap = onTap
        view.onBegin = onBegin
        view.onEnd = onEnd
    }
}

@MainActor
final class OperationDragHandleView: NSView, NSDraggingSource, OperationDragHandleMarker {
    var operationID = ""
    var cardSize = CGSize(width: 240, height: 60)
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    var onTap: () -> Void = {}
    var coversCard = false
    private var pressedEvent: NSEvent?

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 40) }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !coversCard else { return }
        NSColor.secondaryLabelColor.setFill()
        for row in 0..<3 {
            for column in 0..<2 {
                let dot = NSRect(x: bounds.midX - 3.75 + CGFloat(column) * 5,
                                 y: bounds.midY - 6.25 + CGFloat(row) * 5, width: 2.5, height: 2.5)
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    /// The card starts ten points before its first control, with equal vertical
    /// padding. AppKit uses the original mouse-down position to retain the grip.
    var cardDraggingFrame: NSRect {
        coversCard ? bounds : NSRect(x: -10, y: -(cardSize.height - bounds.height) / 2, width: cardSize.width, height: cardSize.height)
    }

    override func mouseDown(with event: NSEvent) { pressedEvent = event }
    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressedEvent != nil
        pressedEvent = nil
        if wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) { onTap() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let pressedEvent else { return }
        let start = convert(pressedEvent.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - start.x, current.y - start.y) >= 3,
              let image = snapshotCard() else { return }
        self.pressedEvent = nil
        let item = NSDraggingItem(pasteboardWriter: operationID as NSString)
        item.setDraggingFrame(cardDraggingFrame, contents: image)
        onBegin()
        let session = beginDraggingSession(with: [item], event: pressedEvent, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func snapshotCard() -> NSImage? {
        var candidate = superview
        while let view = candidate {
            let rect = view.convert(cardDraggingFrame, from: self)
            if view.bounds.contains(rect), let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) {
                view.cacheDisplay(in: rect, to: bitmap)
                let image = NSImage(size: cardDraggingFrame.size)
                image.addRepresentation(bitmap)
                return image
            }
            candidate = view.superview
        }
        return nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onEnd() }
}
