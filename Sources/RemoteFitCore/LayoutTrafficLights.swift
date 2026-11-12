import Foundation
import CoreGraphics

/// Centred traffic-light dots on the layout flyout: metrics, glyphs, and tooltips.
public enum LayoutTrafficLights {
    public static let popoverWidth: CGFloat = 304
    /// Layout grid flyout before this row: 12pt padding, four 60pt tiles, three 8pt gaps, 12pt padding.
    public static let gridPopoverHeight: CGFloat = 288
    /// Tile stack under the rule: 4 × 60 + 3 × 8.
    public static let gridBody: CGFloat = 264
    public static let topInset: CGFloat = 12
    public static let bottomInset: CGFloat = 12
    /// The grid the formula adds after the rule: tiles plus the existing 12pt bottom inset.
    public static let gridSection: CGFloat = gridBody + bottomInset
    public static let rowHeight: CGFloat = 44
    public static let diameter: CGFloat = 28
    public static let hit: CGFloat = 44
    /// Space between the 44pt hit targets, not between the circle edges.
    public static let hitSpacing: CGFloat = 32
    public static let groupWidth: CGFloat = hit * 3 + hitSpacing * 2
    public static let separatorGap: CGFloat = 8
    /// Counted as 1pt in the panel height. The drawn rule is still one physical pixel.
    public static let separatorThickness: CGFloat = 1
    /// 12 + 44 + 8 + 1 + 8 + grid section (tiles and the bottom inset).
    public static let popoverHeight: CGFloat = topInset + rowHeight + separatorGap + separatorThickness + separatorGap + gridSection
    /// How much taller the flyout is than the grid-only panel. The original 12pt top inset stays.
    public static let addedHeight: CGFloat = popoverHeight - gridPopoverHeight
    public static let glyphPointSize: CGFloat = 14
    public static let glyphOpacity: Double = 0.5
    public static let hoverDarken: Double = 0.08
    public static let pressedDarken: Double = 0.15
    public static let disabledOpacity: Double = 0.35

    /// sRGB of #FF5F57, #FEBC2E, #28C840.
    public static func rgb(_ control: WindowControl) -> (red: Double, green: Double, blue: Double) {
        switch control {
        case .close: (Double(0xFF) / 255, Double(0x5F) / 255, Double(0x57) / 255)
        case .minimize: (Double(0xFE) / 255, Double(0xBC) / 255, Double(0x2E) / 255)
        case .fullScreen: (Double(0x28) / 255, Double(0xC8) / 255, Double(0x40) / 255)
        }
    }

    /// What the row knows about the window the layout tiles act on.
    public struct State: Equatable, Sendable {
        public var windowTitle: String?
        public var applicationName: String?
        public var isFullScreen: Bool
        public var operable: Bool

        public init(windowTitle: String? = nil, applicationName: String? = nil, isFullScreen: Bool = false, operable: Bool = false) {
            self.windowTitle = windowTitle
            self.applicationName = applicationName
            self.isFullScreen = isFullScreen
            self.operable = operable
        }

        public static let unavailable = State()

        /// Window title, otherwise the app name. Used only inside the tooltip.
        public var windowName: String? {
            let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return title }
            let app = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return app.isEmpty ? nil : app
        }

        public func title(for control: WindowControl) -> String {
            switch control {
            case .close: "关闭窗口"
            case .minimize: "最小化"
            case .fullScreen: isFullScreen ? "退出全屏" : "全屏"
            }
        }

        public func symbol(for control: WindowControl) -> String {
            switch control {
            case .close: "xmark"
            case .minimize: "minus"
            case .fullScreen: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            }
        }

        /// Action name, with the window name when one can be operated.
        public func toolTip(for control: WindowControl) -> String {
            let action = title(for: control)
            guard operable, let windowName else { return action }
            return "\(action) · \(windowName)"
        }
    }
}
