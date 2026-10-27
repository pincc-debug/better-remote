import Foundation
import CoreGraphics

/// Picking windows for a multi-window layout: slot order is click order.
/// Clicking an already-picked window, or a spot with no window, ends picking early;
/// the layout is then applied to the windows picked so far.
public struct WindowPickSession<ID: Equatable> {
    public enum Outcome: Equatable { case picked(slot: Int), complete, finished }
    public let needed: Int
    public private(set) var picked: [ID] = []
    public init(needed: Int, prepicked: [ID] = []) {
        self.needed = max(1, needed)
        picked = Array(prepicked.prefix(self.needed))
    }
    public var isComplete: Bool { picked.count >= needed }
    /// 1-based slot of a picked window, for its badge.
    public func slot(of id: ID) -> Int? { picked.firstIndex(of: id).map { $0 + 1 } }
    /// `nil` means the click hit no window.
    public mutating func click(_ id: ID?) -> Outcome {
        guard let id, !picked.contains(id) else { return .finished }
        picked.append(id)
        return isComplete ? .complete : .picked(slot: picked.count)
    }
}

/// One on-screen window as listed front to back by the window server (top-left coordinates).
public struct ScreenWindow: Equatable, Sendable {
    public let number: Int
    public let pid: Int32
    public let bounds: CGRect
    public let layer: Int
    public init(number: Int, pid: Int32, bounds: CGRect, layer: Int) {
        self.number = number; self.pid = pid; self.bounds = bounds; self.layer = layer
    }
    /// The frontmost ordinary window under a point, skipping excluded windows (our overlays and panels).
    public static func hit(_ point: CGPoint, in windows: [ScreenWindow], excluding: Set<Int>) -> ScreenWindow? {
        windows.first { $0.layer == 0 && !excluding.contains($0.number) && $0.bounds.width >= 80 && $0.bounds.height >= 60 && $0.bounds.contains(point) }
    }
}
