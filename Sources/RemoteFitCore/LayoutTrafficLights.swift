import Foundation
import CoreGraphics

/// The three window actions on the layout flyout: metrics, labels, and the tooltip window name.
public enum LayoutTrafficLights {
    /// Width of the layout flyout. Unchanged by the action row.
    public static let popoverWidth: CGFloat = 304
    /// Layout grid flyout before the row: 12pt padding, four 60pt tiles, three 8pt gaps, 12pt padding.
    public static let gridPopoverHeight: CGFloat = 288
    /// 12pt inset on each side, so the three buttons share 280pt.
    public static let contentInset: CGFloat = 12
    public static let contentWidth: CGFloat = popoverWidth - contentInset * 2
    public static let buttonSpacing: CGFloat = 8
    public static let buttonWidth: CGFloat = (contentWidth - buttonSpacing * 2) / 3
    public static let rowHeight: CGFloat = 32
    public static let separatorGap: CGFloat = 8
    /// Counted as 1pt in the panel height. The drawn rule is still one physical pixel.
    public static let separatorThickness: CGFloat = 1
    /// 32pt row, 8pt, 1pt line, 8pt.
    public static let addedHeight: CGFloat = rowHeight + separatorGap + separatorThickness + separatorGap
    public static let popoverHeight: CGFloat = gridPopoverHeight + addedHeight
    public static let iconPointSize: CGFloat = 14
    public static let labelPointSize: CGFloat = 12
    public static let labelSpacing: CGFloat = 6
    /// Neutral button fill: black 5% in light, white 8% in dark.
    public static let lightFillOpacity: Double = 0.05
    public static let darkFillOpacity: Double = 0.08
    /// Same hover / press wash as the layout tiles.
    public static let hoverOverlay: Double = 0.08
    public static let pressedOverlay: Double = 0.12
    public static let disabledOpacity: Double = 0.35

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

        /// Window title, otherwise the app name. Shown only in the button tooltip.
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

        /// Tooltip names the window these buttons will act on. No operable window has none.
        public func toolTip(for control: WindowControl) -> String? {
            guard operable else { return nil }
            return windowName
        }
    }
}
