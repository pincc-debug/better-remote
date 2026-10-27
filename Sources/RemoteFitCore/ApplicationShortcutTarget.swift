import Foundation

/// Toolbars and remote input helpers may temporarily activate without switching the user's app.
public enum ApplicationShortcutTarget {
    public static func resolve(frontmost: Int32?, ownPID: Int32, frontmostIsRegular: Bool,
                               recent: [Int32], liveRegularPIDs: Set<Int32>, visibleWindowPIDs: Set<Int32>) -> Int32? {
        let candidate: Int32?
        if let frontmost, frontmost != ownPID, frontmostIsRegular {
            candidate = liveRegularPIDs.contains(frontmost) ? frontmost : nil
        } else {
            candidate = recent.first { $0 != ownPID && liveRegularPIDs.contains($0) }
        }
        // Do not fall back to an older configured app when the last app closes its window.
        guard let candidate, visibleWindowPIDs.contains(candidate) else { return nil }
        return candidate
    }
}
