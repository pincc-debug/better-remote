import Foundation
import CoreGraphics

public enum ApplicationTargetPolicy {
    /// Ignore tiny remote-control indicators, tooltips and helper windows.
    public static func isUsableWindow(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width >= 80 && frame.height >= 60
    }

    public static func resolve(frontmost: Int32?, ownPID: Int32, visibleWindowPIDs: [Int32],
                               recent: [Int32], frontmostWindowUsable: Bool?) -> Int32? {
        var eligible = Set(visibleWindowPIDs)
        eligible.remove(ownPID)
        if let frontmost, frontmostWindowUsable == false { eligible.remove(frontmost) }
        if let frontmost, eligible.contains(frontmost) { return frontmost }
        if let previous = recent.first(where: { eligible.contains($0) }) { return previous }
        return visibleWindowPIDs.first { eligible.contains($0) }
    }
}
