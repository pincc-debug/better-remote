import CoreGraphics

/// One hovered item per surface, driven only by genuine pointer movement.
///
/// Remote touch clients teleport the cursor: a tap is "jump, press, release", so per-view
/// mouseEntered/mouseExited pairs get lost and several items stay highlighted. The tracker
/// keeps a single hovered id, ignores the first sighting and large jumps (teleports), and is
/// cleared by presses, scrolling and leaving the surface.
public struct HoverTracker<ID: Hashable> {
    /// Largest step between consecutive pointer samples still treated as continuous movement.
    public static var maximumStep: CGFloat { 48 }
    public private(set) var hoveredID: ID?
    private var lastPoint: CGPoint?
    public init() {}

    /// Feed every pointer sample (screen or surface coordinates, consistently).
    /// Returns true when `hoveredID` changed.
    @discardableResult
    public mutating func pointerMoved(to point: CGPoint, over id: ID?, buttonDown: Bool = false) -> Bool {
        let before = hoveredID
        defer { lastPoint = buttonDown ? nil : point }
        guard !buttonDown else { hoveredID = nil; return before != nil }
        guard let last = lastPoint else { return false }
        let step = hypot(point.x - last.x, point.y - last.y)
        if step > Self.maximumStep { hoveredID = nil; return before != nil }
        guard step >= 0.5 else { return false }
        hoveredID = id
        return before != hoveredID
    }

    /// Pointer left the surface, a press started or ended, or content scrolled.
    @discardableResult
    public mutating func reset() -> Bool {
        let changed = hoveredID != nil
        hoveredID = nil; lastPoint = nil
        return changed
    }

    /// The hovered item disappeared under the pointer (e.g. its own exit event).
    public mutating func leave(_ id: ID) { if hoveredID == id { hoveredID = nil } }
}

extension HoverTracker: Sendable where ID: Sendable {}
