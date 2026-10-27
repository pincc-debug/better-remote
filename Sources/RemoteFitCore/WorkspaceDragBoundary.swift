import Foundation

/// Quartz coordinates. Changes only window movement/right-edge resizing;
/// content gestures must never be routed through this boundary.
public enum WorkspaceDragBoundary {
    public enum Kind: Sendable { case move, resizeRight, resizeLeft }

    public static func location(_ proposed: CGPoint, start: CGPoint, window: CGRect,
                                area: CGRect, kind: Kind) -> CGPoint {
        var result = proposed
        let right = start.x + area.maxX - window.maxX
        if kind == .resizeLeft {
            result.x = max(result.x, start.x + area.minX - window.minX)
        } else { result.x = min(result.x, right) }
        if kind == .move {
            // A minimum-size window can be larger than the available area.
            // Do not manufacture inverted pointer constraints in that case.
            if window.width <= area.width { result.x = max(result.x, start.x + area.minX - window.minX) }
            if window.height <= area.height {
                result.y = min(max(result.y, start.y + area.minY - window.minY), start.y + area.maxY - window.maxY)
            }
        }
        return result
    }
}
