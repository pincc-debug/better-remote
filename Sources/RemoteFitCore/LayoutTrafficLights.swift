import Foundation
import CoreGraphics

/// Traffic lights on the layout flyout: metrics, the caption for the front window, and tooltips.
public enum LayoutTrafficLights {
    /// Width of the layout flyout. Unchanged by the traffic-light row.
    public static let popoverWidth: CGFloat = 304
    /// Layout grid flyout before the row: 12pt padding, four 60pt tiles, three 8pt gaps, 12pt padding.
    public static let gridPopoverHeight: CGFloat = 288
    /// The row (32pt) plus the 8pt gaps on either side of the hairline.
    public static let addedHeight: CGFloat = 48
    public static let popoverHeight: CGFloat = gridPopoverHeight + addedHeight
    public static let rowHeight: CGFloat = 32
    /// Hairline sits in the middle, so the line does not add a point of its own.
    public static let separatorBand: CGFloat = 16
    public static let diameter: CGFloat = 18
    public static let hit: CGFloat = 32
    public static let centerSpacing: CGFloat = 28
    public static let disabledOpacity: Double = 0.35
    /// Pressed circle is about 10% darker; hover is only slightly darker.
    public static let pressedShade: Double = 0.10
    public static let hoverShade: Double = 0.05
    public static let glyphOpacity: Double = 0.5
    public static let glyphPointSize: CGFloat = 9
    public static let captionPointSize: CGFloat = 12
    public static let unavailableCaption = "没有可操作的窗口"

    /// sRGB of the system traffic lights: #FF5F57, #FEBC2E, #28C840.
    public static func rgb(_ control: WindowControl) -> (red: Double, green: Double, blue: Double) {
        switch control {
        case .close: (Double(0xFF) / 255, Double(0x5F) / 255, Double(0x57) / 255)
        case .minimize: (Double(0xFE) / 255, Double(0xBC) / 255, Double(0x2E) / 255)
        case .fullScreen: (Double(0x28) / 255, Double(0xC8) / 255, Double(0x40) / 255)
        }
    }

    /// Middle ellipsis for a character budget. The flyout uses the same policy, measured by line width.
    public static func middleTruncated(_ text: String, limit: Int) -> String {
        let chars = Array(text)
        guard limit > 0, chars.count > limit else { return text }
        if limit == 1 { return "…" }
        let keep = limit - 1
        let headCount = keep / 2
        let tailCount = keep - headCount
        return String(chars.prefix(headCount)) + "…" + String(chars.suffix(tailCount))
    }

    /// What the row shows for the window the layout tiles are about to act on.
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

        /// Window title, otherwise the app name. No operable window uses the empty-state copy.
        public var caption: String {
            guard operable else { return LayoutTrafficLights.unavailableCaption }
            let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return title }
            let app = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !app.isEmpty { return app }
            return "窗口"
        }

        public func toolTip(for control: WindowControl) -> String {
            switch control {
            case .close: "关闭窗口"
            case .minimize: "最小化"
            case .fullScreen: isFullScreen ? "退出全屏" : "全屏"
            }
        }
    }
}
