import CoreGraphics
import Foundation

/// 远程时窗口自动铺满: decides whether a window that just appeared or came to the front should be filled.
/// Frames are Accessibility (top-left) coordinates; `area` is the same fill target as the toolbar's 铺满.
public enum AutoFillPolicy {
    public struct Window: Equatable, Sendable {
        public var role: String?
        public var subrole: String?
        public var frame: CGRect?
        /// Position and size are both settable.
        public var resizable: Bool
        public var fullScreen: Bool
        public var minimized: Bool
        public var modal: Bool
        /// Window-server layer; only normal windows (0) qualify.
        public var layer: Int
        public var ownApplication: Bool
        public init(role: String?, subrole: String?, frame: CGRect?, resizable: Bool, fullScreen: Bool = false,
                    minimized: Bool = false, modal: Bool = false, layer: Int = 0, ownApplication: Bool = false) {
            self.role = role; self.subrole = subrole; self.frame = frame; self.resizable = resizable
            self.fullScreen = fullScreen; self.minimized = minimized; self.modal = modal
            self.layer = layer; self.ownApplication = ownApplication
        }
    }

    public enum Decision: Equatable, Sendable {
        case fill
        case skip(Reason)
    }
    public enum Reason: Equatable, Sendable {
        case ownApplication, notStandardWindow, modal, notResizable, fullScreen, minimized, floatingLayer, noFrame, tooSmall, alreadyFilled
    }

    public static func decide(_ window: Window, area: CGRect) -> Decision {
        if window.ownApplication { return .skip(.ownApplication) }
        // Dialogs, sheets, panels, popovers, floating and utility windows all have another role or subrole.
        guard window.role == "AXWindow", window.subrole == "AXStandardWindow" else { return .skip(.notStandardWindow) }
        if window.modal { return .skip(.modal) }
        if window.layer != 0 { return .skip(.floatingLayer) }
        if window.minimized { return .skip(.minimized) }
        if window.fullScreen { return .skip(.fullScreen) }
        guard window.resizable else { return .skip(.notResizable) }
        guard let frame = window.frame else { return .skip(.noFrame) }
        guard ApplicationTargetPolicy.isUsableWindow(frame) else { return .skip(.tooSmall) }
        if FillToggle.isFilled(frame, in: area) { return .skip(.alreadyFilled) }
        return .fill
    }

    public static func shouldFill(_ window: Window, area: CGRect) -> Bool { decide(window, area: area) == .fill }
}

/// Remembers which window was auto-filled so a manual resize is respected.
///
/// A window the user resized after auto-fill is left alone while it stays in front; once another window
/// has been in front and it is activated again, it may be filled again.
public struct AutoFillTracker: Sendable {
    public struct Key: Hashable, Sendable {
        public let pid: Int32
        public let window: Int
        public init(pid: Int32, window: Int) { self.pid = pid; self.window = window }
    }
    public private(set) var front: Key?
    private var filled: Set<Key> = []
    public init() {}

    /// Whether this trigger may fill `key`. Call `didFill` after a successful fill.
    public mutating func allows(_ key: Key, frame: CGRect, area: CGRect) -> Bool {
        let reactivated = front != key
        front = key
        if FillToggle.isFilled(frame, in: area) { return false }
        // Same window still in front and no longer at the fill frame: the user resized it.
        if !reactivated, filled.contains(key) { return false }
        return true
    }

    public mutating func didFill(_ key: Key) { filled.insert(key); front = key }

    /// Drop windows that are gone.
    public mutating func retain(_ live: Set<Key>) {
        filled.formIntersection(live)
        if let front, !live.contains(front) { self.front = nil }
    }

    public mutating func reset() { front = nil; filled = [] }
}
