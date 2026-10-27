import Foundation

/// Converts one-finger pointer motion into continuous scroll deltas for scroll mode.
/// Content follows the finger: moving up (negative CG y) scrolls the page down.
public struct ScrollGesture: Sendable {
    /// Movement below this distance (points) between press and release counts as a tap.
    public static let tapSlop: Double = 16
    /// Samples older than this are ignored for release velocity.
    public static let velocityWindow: TimeInterval = 0.1

    private var samples: [(time: TimeInterval, dx: Double, dy: Double)] = []
    private var remainderX = 0.0
    private var remainderY = 0.0

    public init() {}

    public static func isTap(from start: (x: Double, y: Double), to end: (x: Double, y: Double)) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < tapSlop
    }

    public mutating func reset() {
        samples.removeAll()
        remainderX = 0; remainderY = 0
    }

    /// Records finger movement and returns whole-pixel wheel deltas (wheel1 = vertical, wheel2 = horizontal).
    public mutating func record(dx: Double, dy: Double, at time: TimeInterval) -> (vertical: Int32, horizontal: Int32) {
        samples.append((time, dx, dy))
        samples.removeAll { time - $0.time > Self.velocityWindow }
        return quantize(dx: dx, dy: dy)
    }

    /// Finger velocity in points per second over the recent window.
    public func velocity(at time: TimeInterval) -> (dx: Double, dy: Double) {
        let recent = samples.filter { time - $0.time <= Self.velocityWindow }
        guard let first = recent.first, recent.count >= 2 else { return (0, 0) }
        let span = max(time - first.time, 1.0 / 120)
        return (recent.reduce(0) { $0 + $1.dx } / span, recent.reduce(0) { $0 + $1.dy } / span)
    }

    /// Per-frame momentum deltas after release, decaying until imperceptible.
    public static func momentum(velocity: (dx: Double, dy: Double), frameRate: Double = 60,
                                decay: Double = 0.94, minimumSpeed: Double = 150, limit: Int = 180) -> [(dx: Double, dy: Double)] {
        guard hypot(velocity.dx, velocity.dy) >= minimumSpeed else { return [] }
        var frame = (dx: velocity.dx / frameRate, dy: velocity.dy / frameRate)
        var frames: [(dx: Double, dy: Double)] = []
        while hypot(frame.dx, frame.dy) >= 0.5, frames.count < limit {
            frames.append(frame)
            frame = (frame.dx * decay, frame.dy * decay)
        }
        return frames
    }

    /// Accumulates fractional movement so slow drags still scroll.
    public mutating func quantize(dx: Double, dy: Double) -> (vertical: Int32, horizontal: Int32) {
        remainderX += dx; remainderY += dy
        let x = remainderX.rounded(.towardZero), y = remainderY.rounded(.towardZero)
        remainderX -= x; remainderY -= y
        let clamp = { (v: Double) in Int32(max(-2000, min(2000, v))) }
        return (clamp(y), clamp(x))
    }
}

/// Classifies a one-finger press from a remote client: any move past tap slop
/// scrolls; hold still ~0.8 s to get a real drag (like long-press on a phone);
/// release without moving to click.
public enum TouchPressDecision: Equatable, Sendable {
    case undecided, scroll, hold
    public static let holdDelay: TimeInterval = 0.8

    public static func classify(elapsed: TimeInterval, distance: Double) -> Self {
        // Once the finger has moved, it is a scroll — never a late "hold".
        // Long-press drag is only entered by sitting still until holdDelay.
        if distance >= ScrollGesture.tapSlop { return .scroll }
        return elapsed >= holdDelay ? .hold : .undecided
    }

    /// A delayed press must never pull the pointer back after another input moved it.
    public static func replayPoint(start: CGPoint, current: CGPoint) -> CGPoint? {
        hypot(current.x - start.x, current.y - start.y) <= ScrollGesture.tapSlop * 2 ? current : nil
    }
}
