import CoreGraphics

/// 铺满 / 还原 toggle state for the toolbar button. Frames are in Accessibility (top-left) coordinates;
/// `area` is the fill target (visible screen frame minus menu bar, Dock and docked toolbar).
public struct FillToggle: Sendable {
    public struct Key: Hashable, Sendable {
        public let pid: Int32
        /// Window-server number of the AX window that was filled.
        public let window: Int
        public init(pid: Int32, window: Int) { self.pid = pid; self.window = window }
    }
    public static let tolerance: CGFloat = 6
    /// Centered fallback size as a fraction of the area.
    public static let fallbackFraction: CGFloat = 2.0 / 3.0

    private var saved: [Key: CGRect] = [:]
    /// Entries whose window has been seen filled; only these are dropped when the window leaves filled.
    private var confirmed: Set<Key> = []
    public init() {}

    public static func isFilled(_ frame: CGRect, in area: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        abs(frame.minX - area.minX) <= tolerance && abs(frame.minY - area.minY) <= tolerance &&
            abs(frame.maxX - area.maxX) <= tolerance && abs(frame.maxY - area.maxY) <= tolerance
    }

    public static func centered(in area: CGRect) -> CGRect {
        let size = CGSize(width: (area.width * fallbackFraction).rounded(), height: (area.height * fallbackFraction).rounded())
        return CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Keeps a saved frame on screen after a resolution change: shrinks to fit, then moves inside.
    public static func clamp(_ frame: CGRect, in area: CGRect) -> CGRect {
        let width = min(frame.width, area.width), height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public func savedFrame(for key: Key) -> CGRect? { saved[key] }

    /// The frame a press should move the window to, updating the saved state.
    public mutating func target(for key: Key?, current: CGRect, area: CGRect) -> CGRect {
        if Self.isFilled(current, in: area) {
            let restored = key.flatMap { saved[$0] }.map { Self.clamp($0, in: area) }
            if let key { saved[key] = nil; confirmed.remove(key) }
            // A saved frame that is itself (nearly) filled would be a no-op; use the centered size.
            if let restored, !Self.isFilled(restored, in: area) { return restored }
            return Self.centered(in: area)
        }
        if let key { saved[key] = current; confirmed.remove(key) }
        return area
    }

    /// Periodic check of the frontmost window. Returns whether it is filled (button shows 还原).
    /// `liveKeys` are the windows still on screen; saved frames of closed windows are dropped.
    @discardableResult
    public mutating func observe(_ key: Key?, frame: CGRect?, area: CGRect?, liveKeys: Set<Key>? = nil) -> Bool {
        if let liveKeys {
            for gone in saved.keys where !liveKeys.contains(gone) { saved[gone] = nil; confirmed.remove(gone) }
        }
        guard let frame, let area else { return false }
        let filled = Self.isFilled(frame, in: area)
        guard let key, saved[key] != nil else { return filled }
        if filled { confirmed.insert(key) }
        else if confirmed.contains(key) { saved[key] = nil; confirmed.remove(key) }
        return filled
    }
}
