import Foundation

/// Keeps the first preset nearest the dock while preserving order within each row.
public enum ReachablePresetGrid {
    public static func slots(count: Int, columns: Int, side: ToolbarSide) -> [Int?] {
        guard count > 0 else { return [] }
        let columns = max(1, columns)
        var rows: [[Int?]] = stride(from: 0, to: count, by: columns).map { start in
            (0..<columns).map { start + $0 < count ? start + $0 : nil }
        }
        if side == .right { rows = rows.map { Array($0.reversed()) } }
        if side == .bottom { rows.reverse() }
        return rows.flatMap { $0 }
    }
}
