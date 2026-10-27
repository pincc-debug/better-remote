import Foundation
import CoreGraphics

public enum WindowLayout {
    /// Move actual overlaps first; if there is no room, trim only the obstructed edge.
    public static func avoidingToolbar(_ window: CGRect, toolbar: CGRect, screen: CGRect, side: ToolbarSide) -> CGRect? {
        let overlap = window.intersection(toolbar)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return nil }
        var target = window
        switch side {
        case .right: target.origin.x = toolbar.minX - window.width
        case .left: target.origin.x = toolbar.maxX
        case .top: target.origin.y = toolbar.maxY
        case .bottom: target.origin.y = toolbar.minY - window.height
        }
        if screen.contains(target), target.origin != window.origin { return target }
        guard screen.contains(window) else { return nil }
        target = window
        switch side {
        case .right: target.size.width = toolbar.minX - window.minX
        case .left:
            target.origin.x = toolbar.maxX
            target.size.width = window.maxX - toolbar.maxX
        case .top:
            target.origin.y = toolbar.maxY
            target.size.height = window.maxY - toolbar.maxY
        case .bottom: target.size.height = toolbar.minY - window.minY
        }
        guard target.width > 0, target.height > 0, screen.contains(target) else { return nil }
        return target
    }
    public enum Placement: Sendable {
        case maximize, center, moveToScreen
    }

    /// Both rectangles use the accessibility coordinate system (top-left origin).
    public static func frame(_ current: CGRect, in visible: CGRect, placement: Placement) -> CGRect {
        let size = CGSize(width: min(current.width, visible.width), height: min(current.height, visible.height))
        switch placement {
        case .maximize:
            return visible
        case .center:
            return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        case .moveToScreen:
            guard current.intersects(visible) else {
                return frame(current, in: visible, placement: .center)
            }
            return CGRect(x: min(max(current.minX, visible.minX), visible.maxX - size.width),
                          y: min(max(current.minY, visible.minY), visible.maxY - size.height),
                          width: size.width, height: size.height)
        }
    }

    /// Reclaims only the horizontal strip next to a collapsed toolbar.
    public static func fillingCollapsedToolbar(_ window: CGRect, toolbar: CGRect, screen: CGRect,
                                               side: ToolbarSide, tolerance: CGFloat = 10) -> CGRect? {
        guard !side.isHorizontal, screen.contains(window),
              min(window.maxY, toolbar.maxY) > max(window.minY, toolbar.minY) else { return nil }
        let gap = side == .right ? toolbar.minX - window.maxX : window.minX - toolbar.maxX
        guard gap >= 0, gap <= tolerance else { return nil }
        if side == .right {
            return CGRect(x: window.minX, y: window.minY, width: screen.maxX - window.minX, height: window.height)
        }
        return CGRect(x: screen.minX, y: window.minY, width: window.maxX - screen.minX, height: window.height)
    }

    public static func approximatelyEqual(_ first: CGRect, _ second: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(first.minX - second.minX) <= tolerance && abs(first.minY - second.minY) <= tolerance &&
        abs(first.width - second.width) <= tolerance && abs(first.height - second.height) <= tolerance
    }

    /// Text-grid windows can stop slightly short of a requested size. A window
    /// larger than the target is never considered fitted to the screen.
    public static func reached(_ actual: CGRect, target: CGRect, allowsSizeRounding: Bool) -> Bool {
        if approximatelyEqual(actual, target) { return true }
        guard allowsSizeRounding else { return false }
        return abs(actual.minX - target.minX) <= 2 && abs(actual.minY - target.minY) <= 2 &&
            actual.width <= target.width + 2 && actual.height <= target.height + 2 &&
            target.width - actual.width <= 32 && target.height - actual.height <= 32
    }

    public static func waitForFrame(target: CGRect, allowsSizeRounding: Bool = false,
                                    isolation: isolated (any Actor)? = #isolation, read: () throws -> CGRect) async throws -> CGRect {
        let deadline = ContinuousClock.now + .milliseconds(700)
        repeat {
            try Task.checkCancellation()
            let actual = try read()
            if reached(actual, target: target, allowsSizeRounding: allowsSizeRounding) { return actual }
            if ContinuousClock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(50))
        } while true
        throw FitError.message("窗口未完成调整，请重试")
    }

    /// Native zoom owns the final geometry and restore history. Observe a stable
    /// change instead of forcing it to match our calculated desktop rectangle.
    public static func waitForNativeZoom(from original: CGRect, isolation: isolated (any Actor)? = #isolation, read: () throws -> CGRect) async throws -> CGRect {
        let deadline = ContinuousClock.now + .seconds(2)
        var candidate: CGRect?
        var stableReads = 0
        repeat {
            try Task.checkCancellation()
            let actual = try read()
            if !approximatelyEqual(actual, original) {
                stableReads = candidate.map { approximatelyEqual(actual, $0) } == true ? stableReads + 1 : 1
                candidate = actual
                if stableReads >= 3 { return actual }
            } else {
                candidate = nil
                stableReads = 0
            }
            if ContinuousClock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(50))
        } while true
        throw FitError.message("窗口未响应缩放操作")
    }

    /// A disconnected display must not leave a restored window off screen.
    public static func restoredFrame(_ original: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        let target = screen(containing: original, screens: screens, fallback: fallback)
        return frame(original, in: target, placement: .moveToScreen)
    }

    public static func screen(containing window: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        let screen = screens.max { overlap(window, $0) < overlap(window, $1) }
        return screen.flatMap { overlap(window, $0) > 0 ? $0 : nil } ?? fallback
    }

    private static func overlap(_ window: CGRect, _ screen: CGRect) -> CGFloat {
        let intersection = window.intersection(screen)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
