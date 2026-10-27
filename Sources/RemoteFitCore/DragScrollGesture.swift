import CoreGraphics

/// One-finger swipe from a remote touch client arrives as press-drag-release, not scroll wheel.
/// Decides when a drag becomes a scroll and what content offset it maps to.
public struct DragScrollGesture: Sendable {
    public static let threshold: CGFloat = 8
    public let start: CGPoint
    public let startOffset: CGFloat
    public private(set) var isScrolling = false
    public init(start: CGPoint, startOffset: CGFloat) { self.start = start; self.startOffset = startOffset }

    /// `point` in window coordinates (y grows upward). Returns the new top offset
    /// (0 = top, grows downward) once scrolling, nil while it is still a potential click.
    public mutating func drag(to point: CGPoint, maxOffset: CGFloat) -> CGFloat? {
        let dx = point.x - start.x, dy = point.y - start.y
        if !isScrolling {
            guard abs(dy) > Self.threshold, abs(dy) > abs(dx) else { return nil }
            isScrolling = true
        }
        // Finger up (dy > 0) reveals content further down.
        return min(max(0, startOffset + dy), max(0, maxOffset))
    }
}
