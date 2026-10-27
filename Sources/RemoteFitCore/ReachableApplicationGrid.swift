import Foundation
import CoreGraphics

/// Consecutive recent apps fill the column nearest the toolbar, then move inward.
public struct ReachableApplicationGrid: Equatable, Sendable {
    public static let cellHeight: CGFloat = 64
    public static let horizontalSpacing: CGFloat = 8
    public static let verticalSpacing: CGFloat = 8
    public static let minimumCellWidth: CGFloat = 64
    public static let panelHorizontalInsets: CGFloat = 104
    public static let panelVerticalInsets: CGFloat = 48
    public static let horizontalPanelVerticalInsets: CGFloat = panelVerticalInsets + 64
    public static let errorHeight: CGFloat = 56
    public static let pageControlHeight: CGFloat = 90
    public static func pageControlHeight(for width: CGFloat) -> CGFloat { width < 124 ? 154 : pageControlHeight }
    public let count: Int
    public let columns: Int
    public let rows: Int
    public let cellWidth: CGFloat
    public let pages: Int
    public var capacity: Int { columns * rows }

    public init(count: Int, size: CGSize) {
        self.count = max(0, count)
        let width = max(1, size.width)
        func fittingRows(height: CGFloat) -> Int {
            max(1, Int((max(1, height) + Self.verticalSpacing) / (Self.cellHeight + Self.verticalSpacing)))
        }
        let maxColumns = max(1, Int((width + Self.horizontalSpacing) / (Self.minimumCellWidth + Self.horizontalSpacing)))
        let needsPages = self.count > maxColumns * fittingRows(height: size.height)
        let visibleRows = fittingRows(height: size.height - (needsPages ? Self.pageControlHeight(for: width) : 0))
        columns = min(maxColumns, max(1, Int(ceil(Double(self.count) / Double(visibleRows)))))
        rows = min(visibleRows, max(1, self.count))
        pages = max(1, Int(ceil(Double(self.count) / Double(columns * rows))))
        cellWidth = min(Self.minimumCellWidth, width)
    }

    public func indices(inColumn column: Int, side: ToolbarSide, page: Int = 0) -> Range<Int> {
        guard (0..<columns).contains(column), (0..<pages).contains(page) else { return 0..<0 }
        let rank = side == .right ? columns - 1 - column : column
        let start = min(count, page * capacity + rank * rows)
        return start..<min(count, start + rows)
    }
}
