import Foundation
import CoreGraphics

public enum DesktopToolbarLayout {
    public static let width: CGFloat = 72
    public static let buttonHeight: CGFloat = 58
    public static let step: CGFloat = 64
    public static let margin: CGFloat = 8
    public static let collapsedSize: CGFloat = 52
    /// 分辨率, 设置 and 收起; 还原本机 lives in the resolution panel.
    public static let fixedButtonCount = 3
    /// Side toolbars are one narrow column; top/bottom toolbars one row of the same thickness.
    public static let sideWidth: CGFloat = width
    public static let horizontalHeight: CGFloat = buttonHeight + 16

    public static func footerCells(pages: Int = 1, windowControls: Bool = false) -> Int { fixedButtonCount }
    /// Fixed buttons stack in one column after a divider: 窗口 (optional), 分辨率, 设置, 收起.
    public static func footerHeight(columns: Int = 1, pages: Int = 1, windowControls: Bool = false, applicationShortcut: Bool = false) -> CGFloat {
        CGFloat(fixedButtonCount + (windowControls ? 1 : 0) + (applicationShortcut ? 1 : 0)) * footerStep + 8
    }
    /// Fixed buttons are compact rows so the custom operations get more room.
    public static let footerStep: CGFloat = 42
    public static let footerButtonHeight: CGFloat = 38

    /// Window controls (关闭 / 最小化 / 全屏 / 撤回) sit inline as a 2 × 2 grid of 44 pt cells.
    public static let windowControlCount = 4
    public static let windowControlCell: CGFloat = 44
    public static let windowControlGap: CGFloat = 4
    /// Space the group takes along the toolbar, including its divider.
    public static let windowControlsLength: CGFloat = 2 * windowControlCell + windowControlGap + 16

    /// Top inset plus the gap above the fixed groups; the expanded toolbar shows no grip.
    public static let customInset: CGFloat = 8
    public static func chromeHeight(columns: Int, pages: Int = 1, windowControls: Bool = false) -> CGFloat {
        footerHeight(columns: columns, windowControls: windowControls) + customInset * 2
    }

    /// How many custom operations one page shows along `length` points of free toolbar.
    /// Arrows take space only when the operations overflow.
    public static func pageSize(count: Int, length: CGFloat) -> (perPage: Int, pages: Int) {
        let count = max(1, count)
        let fit = max(1, Int((length + step - buttonHeight) / step))
        if count <= fit { return (count, 1) }
        let perPage = max(1, Int((length - pageArrowLength + step - buttonHeight) / step))
        return (perPage, Int(ceil(Double(count) / Double(perPage))))
    }

    /// Custom operations scroll by drag or wheel; no arrows take space.
    public static let pageArrowLength: CGFloat = 0

    public struct Grid: Equatable, Sendable {
        public let columns: Int
        public let rows: Int
        public let pages: Int
        public let footerColumns: Int
        public var windowControls: Bool = false
        public var horizontalFooterWidth: CGFloat { DesktopToolbarLayout.footerHeight(windowControls: windowControls) }
        public var capacity: Int { columns * rows }
        public var showsPageArrows: Bool { pages > 1 }
        public func range(page: Int, count: Int) -> Range<Int> {
            let start = min(count, max(0, min(page, pages - 1)) * capacity)
            return start..<min(count, start + capacity)
        }
    }

    /// Side toolbars are always one column of full-width buttons and top/bottom toolbars one row.
    /// Custom operations that do not fit are paged with arrows; fixed buttons never move.
    public static func grid(in screen: CGRect, count: Int, side: ToolbarSide = .right, windowControls: Bool = false) -> Grid {
        let count = max(1, count)
        if side.isHorizontal {
            let footerColumns = 2
            let room = screen.width - footerHeight(windowControls: windowControls) - customInset * 2
            let page = pageSize(count: count, length: room)
            return Grid(columns: page.perPage, rows: 1, pages: page.pages, footerColumns: footerColumns, windowControls: windowControls)
        }
        // The expanded side toolbar spans the full visible height of its screen.
        let page = pageSize(count: count, length: screen.height - chromeHeight(columns: 1, windowControls: windowControls))
        return Grid(columns: 1, rows: page.perPage, pages: page.pages, footerColumns: 1, windowControls: windowControls)
    }

    /// A flyout opens beside a toolbar button, inward from the docked edge, inside the screen.
    public static func flyout(beside button: CGRect, toolbar: CGRect, in screen: CGRect, size: CGSize, side: ToolbarSide) -> CGRect {
        let width = min(size.width, screen.width - margin * 2), height = min(size.height, screen.height - margin * 2)
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), max(lo, hi)) }
        let x: CGFloat, y: CGFloat
        switch side {
        case .right, .left:
            x = side == .right ? toolbar.minX - margin - width : toolbar.maxX + margin
            y = button.midY - height / 2
        case .top, .bottom:
            x = button.midX - width / 2
            y = side == .top ? toolbar.minY - margin - height : toolbar.maxY + margin
        }
        return CGRect(x: clamp(x, screen.minX + margin, screen.maxX - margin - width),
                      y: clamp(y, screen.minY + margin, screen.maxY - margin - height), width: width, height: height)
    }

    public static func toolbar(in screen: CGRect, centerY: CGFloat, expanded: Bool, count: Int, side: ToolbarSide = .right, centerX: CGFloat? = nil, windowControls: Bool = false) -> CGRect {
        if !expanded {
            let width = min(collapsedSize, max(1, screen.width - margin * 2))
            let height = min(collapsedSize, max(1, screen.height - margin * 2))
            return CGRect(x: screen.maxX - width - margin, y: screen.minY + margin, width: width, height: height)
        }
        let size: CGSize
        if !expanded {
            size = CGSize(width: collapsedSize, height: collapsedSize)
        } else if side.isHorizontal {
            size = CGSize(width: screen.width,
                          height: horizontalHeight)
        } else {
            size = CGSize(width: sideWidth,
                          height: screen.height)
        }
        // Expanded toolbars fill the usable dock edge with no outer inset.
        let width = min(size.width, max(1, screen.width))
        let height = min(size.height, max(1, screen.height))
        func clamped(_ origin: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(origin, lower), max(lower, upper))
        }
        let x: CGFloat
        let y: CGFloat
        switch side {
        case .left, .right:
            // Expanded toolbars sit flush against their screen edge.
            x = side == .right ? screen.maxX - width : screen.minX
            y = expanded ? screen.minY : clamped(centerY - height / 2, lower: screen.minY + margin, upper: screen.maxY - height - margin)
        case .top, .bottom:
            x = expanded ? screen.minX : clamped((centerX ?? screen.midX) - width / 2, lower: screen.minX + margin, upper: screen.maxX - width - margin)
            y = side == .top ? screen.maxY - height : screen.minY
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Window around a glass rect: `padding` of transparent room on each edge for its shadow, clipped to `screen`
    /// (the visible frame) so the window never reaches into the menu bar, the Dock or past the screen edge.
    /// Where the glass sits on that edge the window has no room there; the shadow would be off-screen or under
    /// the menu bar / Dock anyway. The glass itself is never clipped.
    public static func shadowWindow(around glass: CGRect, padding: CGFloat, in screen: CGRect) -> CGRect {
        let outset = glass.insetBy(dx: -padding, dy: -padding)
        let clipped = outset.intersection(screen)
        return clipped.isNull ? outset : clipped.union(glass)
    }

    /// What the toolbar occupies on its screen. Only the expanded bar reserves an edge strip;
    /// the collapsed ball and a hidden toolbar leave the whole visible frame to windows.
    public enum Presence: Equatable, Sendable { case hidden, collapsed, expanded }

    public static func workspace(presence: Presence, toolbar: CGRect, in screen: CGRect, side: ToolbarSide) -> CGRect {
        presence == .expanded ? workspace(avoiding: toolbar, in: screen, side: side) : screen
    }

    public static func workspace(avoiding toolbar: CGRect, in screen: CGRect, side: ToolbarSide) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: toolbar.maxX, y: screen.minY, width: max(1, screen.maxX - toolbar.maxX), height: screen.height)
        case .right:
            return CGRect(x: screen.minX, y: screen.minY, width: max(1, toolbar.minX - screen.minX), height: screen.height)
        case .top:
            return CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: max(1, toolbar.minY - screen.minY))
        case .bottom:
            return CGRect(x: screen.minX, y: toolbar.maxY, width: screen.width, height: max(1, screen.maxY - toolbar.maxY))
        }
    }

    public static func companion(to toolbar: CGRect, in screen: CGRect, preferredSize: CGSize = CGSize(width: 340, height: 560), side: ToolbarSide = .right) -> CGRect {
        if side.isHorizontal {
            let area = workspace(avoiding: toolbar, in: screen, side: side).insetBy(dx: margin, dy: margin)
            let width = min(preferredSize.width, max(1, area.width))
            let height = min(preferredSize.height, max(1, area.height))
            return CGRect(x: min(max(toolbar.midX - width / 2, area.minX), area.maxX - width),
                          y: side == .top ? toolbar.minY - margin - height : toolbar.maxY + margin,
                          width: width, height: height)
        }
        let width = min(preferredSize.width, max(1, side == .right ? toolbar.minX - screen.minX - margin * 2 : screen.maxX - toolbar.maxX - margin * 2))
        let height = min(preferredSize.height, max(1, screen.height - margin * 2))
        return CGRect(x: side == .right ? toolbar.minX - margin - width : toolbar.maxX + margin,
                      y: min(max(toolbar.maxY - height, screen.minY + margin), screen.maxY - height - margin),
                      width: width, height: height)
    }

    /// Match the toolbar along its docked edge and expand 80% into the desktop.
    /// Keep the extent stable as recent/running sections change.
    public static func applications(to toolbar: CGRect, in screen: CGRect, side: ToolbarSide = .right) -> CGRect {
        let available = workspace(avoiding: toolbar, in: screen, side: side)
        let width = side.isHorizontal ? toolbar.width : min(screen.width * 0.8, available.width)
        let height = side.isHorizontal ? min(screen.height * 0.8, available.height) : toolbar.height
        let x: CGFloat
        let y: CGFloat
        switch side {
        case .left:
            x = toolbar.maxX
            y = toolbar.minY
        case .right:
            x = toolbar.minX - width
            y = toolbar.minY
        case .top:
            x = toolbar.minX
            y = toolbar.minY - height
        case .bottom:
            x = toolbar.minX
            y = toolbar.maxY
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Resolution controls occupy at most three columns, so the panel follows
    /// their width instead of reserving an otherwise empty half of the desktop.
    public static func resolutionPanel(to toolbar: CGRect, in screen: CGRect, side: ToolbarSide = .right, presetCount: Int) -> CGRect {
        let available = expandedPanel(to: toolbar, in: screen, side: side)
        let columns = max(1, min(3, presetCount))
        let contentWidth = max(280, CGFloat(columns) * 160 + CGFloat(columns - 1) * 8)
        let width = min(available.width, contentWidth + 32)
        if side.isHorizontal {
            // Top / bottom docks fill the whole workspace between the toolbar and the far edge.
            let area = workspace(avoiding: toolbar, in: screen, side: side)
            return CGRect(x: available.minX, y: side == .top ? toolbar.minY - area.height : toolbar.maxY,
                          width: width, height: area.height)
        }
        // Side docks: top and bottom flush with the toolbar so panel + toolbar read as one column.
        return CGRect(x: side == .right ? available.maxX - width : available.minX,
                      y: toolbar.minY, width: width, height: toolbar.height)
    }

    public static func expandedPanel(to toolbar: CGRect, in screen: CGRect, side: ToolbarSide = .right) -> CGRect {
        if side.isHorizontal {
            let area = workspace(avoiding: toolbar, in: screen, side: side)
            let height = max(1, area.height / 2)
            return CGRect(x: toolbar.minX,
                          y: side == .top ? toolbar.minY - height : toolbar.maxY,
                          width: max(1, toolbar.width), height: height)
        }
        let availableWidth = max(1, side == .right ? toolbar.minX - screen.minX - margin * 2 : screen.maxX - toolbar.maxX - margin * 2)
        let panelWidth = max(1, availableWidth / 2)
        return CGRect(x: side == .right ? toolbar.minX - panelWidth : toolbar.maxX,
                      y: screen.minY, width: panelWidth, height: max(1, screen.height))
    }
}
