import Foundation

public enum WindowPlacementResult: Sendable, Equatable {
    case placed, sizeLimited
}

public enum WindowPlacement {
    /// Accept a successfully moved window whose application enforces a larger
    /// size, and keep the corresponding slot edge inside the available desktop.
    public static func constrainedFrame(_ actual: CGRect, target: CGRect, in area: CGRect) -> CGRect? {
        guard !actual.isNull, !actual.isInfinite, actual.width > 0, actual.height > 0,
              target.width > 0, target.height > 0,
              actual.width > target.width + 2 || actual.height > target.height + 2,
              actual.width <= area.width + 2, actual.height <= area.height + 2,
              actual.width >= target.width - 32, actual.height >= target.height - 32 else { return nil }
        // A window still filling the entire split axis has not formed a split.
        if target.width < area.width - 2, actual.width >= area.width - 2 { return nil }
        if target.height < area.height - 2, actual.height >= area.height - 2 { return nil }
        func origin(start: CGFloat, end: CGFloat, areaStart: CGFloat, areaEnd: CGFloat, size: CGFloat) -> CGFloat {
            let aligned: CGFloat
            if abs(start - areaStart) <= 2 { aligned = areaStart }
            else if abs(end - areaEnd) <= 2 { aligned = areaEnd - size }
            else { aligned = (start + end - size) / 2 }
            return min(max(aligned, areaStart), areaEnd - size)
        }
        let frame = CGRect(x: origin(start: target.minX, end: target.maxX, areaStart: area.minX, areaEnd: area.maxX, size: actual.width),
                           y: origin(start: target.minY, end: target.maxY, areaStart: area.minY, areaEnd: area.maxY, size: actual.height),
                           width: actual.width, height: actual.height)
        guard (abs(actual.minX - target.minX) <= 2 || abs(actual.minX - frame.minX) <= 2),
              (abs(actual.minY - target.minY) <= 2 || abs(actual.minY - frame.minY) <= 2) else { return nil }
        return frame
    }
}
