import CoreGraphics

/// Settings window geometry. On a normal desktop the window keeps its 900 × 720 size; on a
/// narrow or short screen (e.g. a phone-portrait resolution while remoting) it shrinks to the
/// screen's visible area so nothing is ever cut off.
public enum SettingsWindowLayout {
    public static let preferredSize = CGSize(width: 900, height: 720)
    /// Smallest window we shrink to before giving up and simply using the whole visible area.
    public static let minimumSize = CGSize(width: 360, height: 360)
    /// Gap kept between the window and the visible-area edges when the screen is too small.
    public static let screenMargin: CGFloat = 12
    /// Below this content width the sidebar collapses to icons and wide controls wrap.
    public static let narrowThreshold: CGFloat = 560
    public static let regularSidebarWidth: CGFloat = 160
    public static let compactSidebarWidth: CGFloat = 56

    public static func isNarrow(contentWidth: CGFloat) -> Bool { contentWidth < narrowThreshold }

    /// Gap kept between 设置 and an expanded desktop toolbar.
    public static let toolbarGap: CGFloat = 8

    /// `area` (the 铺满 area) with a small gap on the toolbar's side when it is smaller than `visible`,
    /// i.e. when an expanded toolbar was subtracted.
    public static func spacedFromToolbar(_ area: CGRect, visible: CGRect, side: ToolbarSide) -> CGRect {
        guard area != visible else { return area }
        var spaced = area
        switch side {
        case .left: spaced.origin.x += toolbarGap; spaced.size.width -= toolbarGap
        case .right: spaced.size.width -= toolbarGap
        case .top: spaced.size.height -= toolbarGap
        case .bottom: spaced.origin.y += toolbarGap; spaced.size.height -= toolbarGap
        }
        return spaced.width > 0 && spaced.height > 0 ? spaced : area
    }

    /// Gap kept between a settings sheet and each visible-area edge.
    public static let dialogMargin: CGFloat = 16

    /// Largest size a settings sheet may take on a screen with this visible area.
    public static func dialogLimit(in visible: CGRect) -> CGSize {
        CGSize(width: max(0, visible.width - 2 * dialogMargin), height: max(0, visible.height - 2 * dialogMargin))
    }

    /// A sheet's designed size, shrunk to `limit` on small screens. `nil` height means content-sized.
    public static func dialogSize(width: CGFloat, height: CGFloat?, limit: CGSize) -> (width: CGFloat, height: CGFloat?) {
        (min(width, limit.width), height.map { min($0, limit.height) })
    }

    /// Largest frame size (preferred size at most) that fits `visible` with margins.
    /// `chrome` is the frame size minus the content size (title bar etc.).
    public static func frameSize(in visible: CGRect, chrome: CGSize = .zero) -> CGSize {
        CGSize(width: fit(preferredSize.width + chrome.width, minimum: minimumSize.width + chrome.width, available: visible.width),
               height: fit(preferredSize.height + chrome.height, minimum: minimumSize.height + chrome.height, available: visible.height))
    }

    /// `frame` resized to `frameSize(in:)` and moved fully inside `visible`. A frame that already
    /// fits keeps its position; one that has to shrink or move is centred on the visible area.
    public static func clampedFrame(_ frame: CGRect, in visible: CGRect, chrome: CGSize = .zero) -> CGRect {
        let size = frameSize(in: visible, chrome: chrome)
        if frame.size == size, visible.contains(frame) { return frame }
        var result = CGRect(origin: frame.origin, size: size)
        if frame.size != size {
            result.origin = CGPoint(x: (visible.midX - size.width / 2).rounded(.down), y: (visible.midY - size.height / 2).rounded(.down))
        }
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - size.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - size.height)
        return result
    }

    private static func fit(_ preferred: CGFloat, minimum: CGFloat, available: CGFloat) -> CGFloat {
        guard available > 0 else { return preferred }
        if preferred + 2 * screenMargin <= available { return preferred }
        // Too small: use the screen minus margins, but never below the minimum unless the
        // screen itself is smaller — then use the whole visible area.
        let withMargins = max(minimum, available - 2 * screenMargin)
        return min(withMargins, available).rounded(.down)
    }
}
