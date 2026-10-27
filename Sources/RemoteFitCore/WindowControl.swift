import Foundation
import CoreGraphics

/// Fixed macOS-style window controls on the toolbar, performed through Accessibility
/// rather than keyboard shortcuts.
public enum WindowControl: String, CaseIterable, Sendable {
    case close, minimize, fullScreen
    /// Buttons shown in the 窗口 panel.
    public static var panelControls: [WindowControl] { allCases }

    public var title: String {
        switch self {
        case .close: "关闭"
        case .minimize: "最小化"
        case .fullScreen: "全屏"
        }
    }

    /// Glyph drawn inside the coloured circle, matching the system traffic lights.
    public var glyph: String {
        switch self {
        case .close: "xmark"
        case .minimize: "minus"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// sRGB components of the standard traffic-light colours.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .close: (1.0, 0.373, 0.341)
        case .minimize: (0.996, 0.737, 0.180)
        case .fullScreen: (0.157, 0.784, 0.251)
        }
    }

    public var unavailableMessage: String {
        switch self {
        case .close: "当前窗口不能关闭"
        case .minimize: "当前窗口不能最小化"
        case .fullScreen: "当前窗口不支持全屏或缩放"
        }
    }
}

/// Picks the window the traffic lights act on: the focused window, then the main
/// window, then the first ordinary window that is not minimized.
public enum WindowControlTarget {
    public struct Candidate: Equatable, Sendable {
        public var focused: Bool
        public var main: Bool
        public var minimized: Bool
        public var usable: Bool
        public init(focused: Bool = false, main: Bool = false, minimized: Bool = false, usable: Bool = true) {
            self.focused = focused; self.main = main; self.minimized = minimized; self.usable = usable
        }
        var eligible: Bool { usable && !minimized }
    }

    public static func select(_ candidates: [Candidate]) -> Int? {
        candidates.firstIndex { $0.focused && $0.eligible }
            ?? candidates.firstIndex { $0.main && $0.eligible }
            ?? candidates.firstIndex(where: \.eligible)
    }

    public enum Method: Equatable, Sendable {
        case press(String), setMinimized, toggleFullScreen, commandW, unavailable
    }

    /// Which Accessibility route to use, given what the window exposes.
    /// Green toggles native full screen when the window supports it, else presses zoom.
    public static func method(for control: WindowControl, hasCloseButton: Bool, hasMinimizeButton: Bool,
                              canSetMinimized: Bool, canSetFullScreen: Bool, hasZoomButton: Bool) -> Method {
        switch control {
        case .close: hasCloseButton ? .press("AXCloseButton") : .commandW
        case .minimize: hasMinimizeButton ? .press("AXMinimizeButton") : (canSetMinimized ? .setMinimized : .unavailable)
        case .fullScreen: canSetFullScreen ? .toggleFullScreen : (hasZoomButton ? .press("AXZoomButton") : .unavailable)
        }
    }
}

/// Layouts offered by long-pressing the green button. Frames are in Accessibility
/// coordinates (top-left origin), matching AXPosition / AXSize.
public enum WindowSnap: String, CaseIterable, Sendable {
    case fill, left, right, top, bottom, center

    public var title: String {
        switch self {
        case .fill: "填充"
        case .left: "左半屏"
        case .right: "右半屏"
        case .top: "上半屏"
        case .bottom: "下半屏"
        case .center: "居中"
        }
    }

    public var symbol: String {
        switch self {
        case .fill: "rectangle.inset.filled"
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        case .top: "rectangle.tophalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        case .center: "rectangle.center.inset.filled"
        }
    }

    /// `area` is the visible frame (menu bar and Dock excluded) of the window's screen.
    public func frame(current: CGRect, in area: CGRect) -> CGRect {
        let halfWidth = (area.width / 2).rounded(.down), halfHeight = (area.height / 2).rounded(.down)
        switch self {
        case .fill: return area
        case .left: return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .right: return CGRect(x: area.maxX - halfWidth, y: area.minY, width: halfWidth, height: area.height)
        case .top: return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottom: return CGRect(x: area.minX, y: area.maxY - halfHeight, width: area.width, height: halfHeight)
        case .center:
            // A comfortable centered window: about 70% wide, 80% tall.
            let size = CGSize(width: (area.width * 0.7).rounded(), height: (area.height * 0.8).rounded())
            return CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
        }
    }

    /// Converts an AppKit screen rect (bottom-left origin) to Accessibility coordinates.
    public static func accessibilityRect(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen holding most of the window; falls back to the first screen.
    public static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { $0.intersection(window).isNull ? 0 : $0.intersection(window).width * $0.intersection(window).height }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        return screens.firstIndex { $0.contains(CGPoint(x: window.midX, y: window.midY)) } ?? 0
    }
}

/// Multi-window arrangements. Windows are picked by the user; slot 1 is the primary
/// (largest, or leftmost/topmost when equal) region.
public enum WindowArrangement: String, CaseIterable, Sendable {
    case halves, verticalHalves, mainAndStack, stackAndMain, topAndPair, pairAndBottom
    case thirds, wideLeft, wideRight, wideCenter, grid

    public var title: String {
        switch self {
        case .halves: "左右平分"
        case .verticalHalves: "上下平分"
        case .mainAndStack: "左一右二"
        case .stackAndMain: "左二右一"
        case .topAndPair: "上一下二"
        case .pairAndBottom: "上二下一"
        case .thirds: "三列平分"
        case .wideLeft: "左大右小"
        case .wideRight: "左小右大"
        case .wideCenter: "中间大两侧小"
        case .grid: "田字格"
        }
    }
    public var windowCount: Int { units.count }

    /// Regions as fractions of the area (top-left origin), in slot order.
    public var units: [CGRect] {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let third: CGFloat = 1.0 / 3
        switch self {
        case .halves: return [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 1)]
        case .verticalHalves: return [r(0, 0, 1, 0.5), r(0, 0.5, 1, 0.5)]
        case .mainAndStack: return [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]
        case .stackAndMain: return [r(0.5, 0, 0.5, 1), r(0, 0, 0.5, 0.5), r(0, 0.5, 0.5, 0.5)]
        case .topAndPair: return [r(0, 0, 1, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]
        case .pairAndBottom: return [r(0, 0.5, 1, 0.5), r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5)]
        case .thirds: return [r(0, 0, third, 1), r(third, 0, third, 1), r(2 * third, 0, 1 - 2 * third, 1)]
        case .wideLeft: return [r(0, 0, 2 * third, 1), r(2 * third, 0, 1 - 2 * third, 1)]
        case .wideRight: return [r(third, 0, 1 - third, 1), r(0, 0, third, 1)]
        case .wideCenter: return [r(0.25, 0, 0.5, 1), r(0, 0, 0.25, 1), r(0.75, 0, 0.25, 1)]
        case .grid: return [r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]
        }
    }

    /// Frames in slot order for the first `available` slots.
    public func frames(available: Int, in area: CGRect) -> [CGRect] {
        let count = min(max(available, 0), windowCount)
        let a = area.integral
        // Fewer windows fill the first slots in order (e.g. one window in 左右平分 takes the left half).
        return units.prefix(count).map { u in
            let x0 = (a.minX + u.minX * a.width).rounded(), x1 = (a.minX + u.maxX * a.width).rounded()
            let y0 = (a.minY + u.minY * a.height).rounded(), y1 = (a.minY + u.maxY * a.height).rounded()
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}

/// 排列: tiles windows over an area, first window (the frontmost) in the primary slot.
public enum WindowTiling {
    public static func frames(count: Int, in area: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let a = area.integral
        func cell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: a.minX + x, y: a.minY + y, width: w, height: h).integral
        }
        let halfW = (a.width / 2).rounded(.down), halfH = (a.height / 2).rounded(.down)
        switch count {
        case 1: return [a]
        case 2: return [cell(0, 0, halfW, a.height), cell(halfW, 0, a.width - halfW, a.height)]
        case 3: return [cell(0, 0, halfW, a.height), cell(halfW, 0, a.width - halfW, halfH), cell(halfW, halfH, a.width - halfW, a.height - halfH)]
        default:
            let columns = Int(ceil(Double(count).squareRoot()))
            let rows = Int(ceil(Double(count) / Double(columns)))
            var result: [CGRect] = []
            for row in 0..<rows {
                let inRow = min(columns, count - row * columns)
                let y0 = (a.height * CGFloat(row) / CGFloat(rows)).rounded(.down)
                let y1 = (a.height * CGFloat(row + 1) / CGFloat(rows)).rounded(.down)
                for column in 0..<inRow {
                    let x0 = (a.width * CGFloat(column) / CGFloat(inRow)).rounded(.down)
                    let x1 = (a.width * CGFloat(column + 1) / CGFloat(inRow)).rounded(.down)
                    result.append(cell(x0, y0, x1 - x0, y1 - y0))
                }
            }
            return result
        }
    }

    /// Ordinary windows worth arranging: not tiny, not our own, on the chosen screen.
    public static func eligible(_ frame: CGRect, on screen: CGRect, minimized: Bool, isOwn: Bool, isStandard: Bool) -> Bool {
        !minimized && !isOwn && isStandard && frame.width >= 160 && frame.height >= 120 && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}
