import CoreGraphics

/// Selection and keyboard state of a custom dropdown (GlassDropdown). Pure and UI-free.
/// Opening highlights the selected item (else the first); ↑/↓ move without wrapping; ⏎ commits.
public struct DropdownSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var items: [ID]
    public private(set) var selected: ID?
    public private(set) var highlighted: Int?
    public private(set) var isOpen = false

    public init(items: [ID], selected: ID?) {
        self.items = items
        self.selected = selected
    }

    public mutating func update(items: [ID], selected: ID?) {
        self.items = items
        self.selected = selected
        if let highlighted, !items.indices.contains(highlighted) { self.highlighted = items.isEmpty ? nil : items.count - 1 }
    }

    public mutating func open() {
        guard !items.isEmpty else { return }
        isOpen = true
        highlighted = selected.flatMap { items.firstIndex(of: $0) } ?? 0
    }

    public mutating func close() { isOpen = false; highlighted = nil }

    public mutating func toggle() { isOpen ? close() : open() }

    public mutating func moveDown() {
        guard isOpen, !items.isEmpty else { open(); return }
        highlighted = min((highlighted ?? -1) + 1, items.count - 1)
    }

    public mutating func moveUp() {
        guard isOpen, !items.isEmpty else { open(); return }
        highlighted = max((highlighted ?? items.count) - 1, 0)
    }

    public mutating func hover(_ index: Int) {
        guard isOpen, items.indices.contains(index) else { return }
        highlighted = index
    }

    /// ⏎ or click: selects the highlighted (or given) item and closes. Returns the item only when it changed.
    @discardableResult
    public mutating func commit(_ index: Int? = nil) -> ID? {
        guard isOpen, let index = index ?? highlighted, items.indices.contains(index) else { close(); return nil }
        let item = items[index]
        let changed = item != selected
        selected = item
        close()
        return changed ? item : nil
    }

    // MARK: Placement

    public enum Edge: Equatable, Sendable { case below, above }

    /// Below the trigger when it fits in `bounds`, else above when that fits better. AppKit (bottom-left) coordinates.
    public static func edge(trigger: CGRect, menuHeight: CGFloat, gap: CGFloat, bounds: CGRect) -> Edge {
        let roomBelow = trigger.minY - gap - bounds.minY
        let roomAbove = bounds.maxY - (trigger.maxY + gap)
        if menuHeight <= roomBelow { return .below }
        return roomAbove > roomBelow ? .above : .below
    }

    /// Menu frame: same leading edge and at least the trigger's width, kept inside `bounds`.
    public static func menuFrame(trigger: CGRect, size: CGSize, gap: CGFloat, bounds: CGRect) -> CGRect {
        let width = max(size.width, trigger.width)
        let edge = edge(trigger: trigger, menuHeight: size.height, gap: gap, bounds: bounds)
        let room = edge == .below ? trigger.minY - gap - bounds.minY : bounds.maxY - trigger.maxY - gap
        let height = min(size.height, max(0, room))
        let y = edge == .below ? trigger.minY - gap - height : trigger.maxY + gap
        let x = min(max(trigger.minX, bounds.minX), bounds.maxX - width)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Keys a dropdown menu handles while open (macOS virtual key codes).
public enum DropdownKey: Equatable, Sendable {
    case up, down, commit, cancel
    public init?(keyCode: UInt16) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76, 49: self = .commit // Return, keypad Enter, Space
        case 53: self = .cancel // Esc
        default: return nil
        }
    }
}
