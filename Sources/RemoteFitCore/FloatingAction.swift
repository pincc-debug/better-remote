import Foundation

public enum FloatingAction: String, Codable, CaseIterable, Sendable {
    case runningApplications, resolution, restoreDisplay, settings
    case maximizeWindow, centerWindow
    /// 铺满: same as the 窗口 panel's 填充 (frontmost window to the layout area).
    case fillWindow
    /// 最小化: minimizes the frontmost window (same as the old 窗口 panel control).
    case minimizeWindow
    /// 清理桌面: minimizes every window on the current desktop.
    case showDesktop
    public static let defaults: [Self] = [.runningApplications, .fillWindow, .minimizeWindow, .showDesktop]
    public static let persistentActions: [Self] = [.resolution, .settings, .restoreDisplay]
    public static var configurableActions: [Self] { allCases.filter { !persistentActions.contains($0) } }
    public var title: String {
        switch self {
        case .runningApplications: "应用"
        case .resolution: "分辨率"
        case .restoreDisplay: "还原"
        case .settings: "设置"
        case .maximizeWindow: "最大化"
        case .centerWindow: "窗口居中"
        case .fillWindow: "铺满"
        case .minimizeWindow: "最小化"
        case .showDesktop: "清理桌面"
        }
    }
    /// Hover text when the caption alone does not say what happens.
    public var hint: String? {
        switch self {
        case .showDesktop: "最小化所有窗口"
        default: nil
        }
    }
    public var symbol: String {
        switch self {
        case .runningApplications: "square.grid.2x2"
        case .resolution: "display.2"
        case .restoreDisplay: "arrow.uturn.backward.circle"
        case .settings: "gearshape"
        case .maximizeWindow: "arrow.up.left.and.arrow.down.right"
        case .centerWindow: "macwindow"
        case .fillWindow: ShortcutIcon.fillWindow.rawValue
        case .minimizeWindow: ShortcutIcon.minimizeWindow.rawValue
        case .showDesktop: "rectangle.on.rectangle.slash"
        }
    }
}

extension FloatingAction {
    /// 铺满 shown while the frontmost window is already filled: same square, arrows inward.
    public static let restoreFillTitle = "还原"
    public static let restoreFillSymbol = "arrow.down.right.and.arrow.up.left.square"
}
