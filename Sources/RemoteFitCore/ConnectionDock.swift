import CoreGraphics


/// 连接自动化 · 连接时的程序坞: what to do with the Dock's 自动隐藏 while a remote session is connected.
public enum ConnectionDockMode: String, Codable, CaseIterable, Sendable {
    /// 保持现状: never touch the Dock (default).
    case keep
    /// 始终显示: autohide off while connected.
    case alwaysShow
    /// 自动隐藏: autohide on while connected (the Dock appears when the pointer reaches the edge).
    case autoHide

    public var title: String {
        switch self {
        case .keep: "保持现状"
        case .alwaysShow: "始终显示"
        case .autoHide: "自动隐藏"
        }
    }

    /// The Dock autohide value this mode wants while connected; nil = leave it alone.
    public var targetAutohide: Bool? {
        switch self {
        case .keep: nil
        case .alwaysShow: false
        case .autoHide: true
        }
    }

    /// Pre-0.8.146 「连接时显示」 on → 始终显示; off or missing → 保持现状.
    public static func migrated(autoShowDockOnConnect: Bool?) -> ConnectionDockMode {
        autoShowDockOnConnect == true ? .alwaysShow : .keep
    }
}

/// Remembers the user's own Dock autohide value while Better Remote has changed it, so it can be put back
/// on disconnect, quit, or the next launch after a crash. Pure decisions only; the caller reads and writes the Dock.
public struct ConnectionDockSession: Codable, Equatable, Sendable {
    /// Non-nil while we changed the Dock and still owe the user this original value.
    public private(set) var originalAutohide: Bool?

    public init(originalAutohide: Bool? = nil) { self.originalAutohide = originalAutohide }

    public var owesRestore: Bool { originalAutohide != nil }

    /// Whether a sync with this mode could need to read the Dock at all.
    /// 保持现状 with nothing owed never touches the Dock (and never triggers the permission prompt).
    public func needsDock(for mode: ConnectionDockMode) -> Bool {
        mode.targetAutohide != nil || owesRestore
    }

    /// Bring the Dock in line with `mode`, given its current autohide value. Returns the value to write, or nil
    /// when nothing needs to change. 保持现状 gives back anything still owed.
    public mutating func apply(mode: ConnectionDockMode, current: Bool) -> Bool? {
        guard let target = mode.targetAutohide else { return restore(current: current) }
        if let original = originalAutohide {
            // Switching to a target that equals the user's own value is the same as giving it back.
            if target == original { return restore(current: current) }
            return current == target ? nil : target
        }
        guard current != target else { return nil }
        originalAutohide = current
        return target
    }

    /// Give back the user's original value. Returns the value to write, or nil when nothing is owed
    /// or the Dock already matches it.
    public mutating func restore(current: Bool) -> Bool? {
        guard let original = originalAutohide else { return nil }
        originalAutohide = nil
        return current == original ? nil : original
    }
}

/// After 连接时的程序坞 changes the Dock, windows that were filling a screen's old work area follow it to the new
/// one (shrink above an always-shown Dock, grow back when it auto-hides). Windows the user arranged any other way stay put.
/// Frames are Accessibility (top-left) coordinates.
public enum DockRefit {
    public struct Area: Equatable, Sendable {
        public var old: CGRect
        public var new: CGRect
        public init(old: CGRect, new: CGRect) { self.old = old; self.new = new }
    }
    public struct Move: Equatable, Sendable {
        public let window: ScreenWindow
        public let target: CGRect
        public init(window: ScreenWindow, target: CGRect) { self.window = window; self.target = target }
    }

    /// Whether the work area actually moved (beyond rounding), i.e. the Dock change has landed.
    public static func changed(_ area: Area) -> Bool {
        !FillToggle.isFilled(area.new, in: area.old, tolerance: 1)
    }

    /// The windows to re-fit and where. Only normal-layer windows of other apps whose frame matches a changed
    /// old area (within the 铺满 tolerance) move, to that screen's new area.
    public static func plan(windows: [ScreenWindow], areas: [Area], excludingPID: Int32) -> [Move] {
        let changedAreas = areas.filter(changed)
        guard !changedAreas.isEmpty else { return [] }
        return windows.compactMap { window in
            guard window.layer == 0, window.pid != excludingPID else { return nil }
            guard let area = changedAreas.first(where: { FillToggle.isFilled(window.bounds, in: $0.old) }) else { return nil }
            return Move(window: window, target: area.new)
        }
    }
}
