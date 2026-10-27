import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class ReachableApplicationGridTests: XCTestCase {
    func testTwentyAppsFitWithoutReducingTouchTargetsBelowMinimum() {
        let size = CGSize(width: 528, height: 470)
        let grid = ReachableApplicationGrid(count: 20, size: size)
        XCTAssertGreaterThanOrEqual(grid.capacity, 20)
        XCTAssertEqual(grid.pages, 1)
        XCTAssertLessThanOrEqual(CGFloat(grid.rows) * ReachableApplicationGrid.cellHeight + CGFloat(grid.rows - 1) * ReachableApplicationGrid.verticalSpacing, size.height)
        XCTAssertLessThanOrEqual(CGFloat(grid.columns) * grid.cellWidth + CGFloat(grid.columns - 1) * ReachableApplicationGrid.horizontalSpacing, size.width)
        XCTAssertGreaterThanOrEqual(grid.cellWidth, ReachableApplicationGrid.minimumCellWidth)
        XCTAssertGreaterThanOrEqual(ReachableApplicationGrid.cellHeight, 44)
    }

    func testNewestAppsFillTheNearestColumnAndMirrorWithToolbarSide() {
        let grid = ReachableApplicationGrid(count: 16, size: CGSize(width: 528, height: 470))
        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 6)
        XCTAssertEqual(Array(grid.indices(inColumn: 2, side: .right)), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(Array(grid.indices(inColumn: 1, side: .right)), [6, 7, 8, 9, 10, 11])
        XCTAssertEqual(Array(grid.indices(inColumn: 0, side: .left)), [0, 1, 2, 3, 4, 5])
        let all = (0..<grid.columns).flatMap { grid.indices(inColumn: $0, side: .right) }
        XCTAssertEqual(all.sorted(), Array(0..<16))
    }

    func testFewAppsStayInOneColumnAndNarrowPanelsDoNotOverflow() {
        let few = ReachableApplicationGrid(count: 2, size: CGSize(width: 528, height: 470))
        XCTAssertEqual(few.columns, 1)
        XCTAssertEqual(few.rows, 2)
        let narrow = ReachableApplicationGrid(count: 16, size: CGSize(width: 168, height: 470))
        XCTAssertEqual(narrow.columns, 2)
        XCTAssertLessThanOrEqual(narrow.cellWidth, 168)
        XCTAssertEqual(narrow.pages, 2)
        XCTAssertLessThanOrEqual(CGFloat(narrow.rows) * ReachableApplicationGrid.cellHeight + CGFloat(narrow.rows - 1) * ReachableApplicationGrid.verticalSpacing + ReachableApplicationGrid.pageControlHeight, 470)
        let indices = (0..<narrow.pages).flatMap { page in
            (0..<narrow.columns).flatMap { narrow.indices(inColumn: $0, side: .right, page: page) }
        }
        XCTAssertEqual(indices.sorted(), Array(0..<16))
    }

    func testPartialColumnsContainNoHolesOrRepeatedApps() {
        let grid = ReachableApplicationGrid(count: 11, size: CGSize(width: 528, height: 470))
        for side in ToolbarSide.allCases {
            let indices = (0..<grid.columns).flatMap { grid.indices(inColumn: $0, side: side) }
            XCTAssertEqual(indices.sorted(), Array(0..<11))
        }
    }

    func testColumnsFillAvailableHeightBeforeMovingInward() {
        let grid = ReachableApplicationGrid(count: 7, size: CGSize(width: 528, height: 470))
        XCTAssertEqual(grid.rows, 6)
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(Array(grid.indices(inColumn: 1, side: .right)), Array(0..<6))
        XCTAssertEqual(Array(grid.indices(inColumn: 0, side: .right)), [6])
        XCTAssertEqual(Array(grid.indices(inColumn: 0, side: .left)), Array(0..<6))
    }

    func testRecentAndAllKeepTheSameCompactColumnWidth() {
        for width in [136.0, 528.0, 712.0, 1536.0] {
            for count in [2, 16, 70, 200] {
                let grid = ReachableApplicationGrid(count: count, size: CGSize(width: width, height: 936))
                XCTAssertEqual(grid.cellWidth, 64)
                XCTAssertEqual(grid.cellWidth + ReachableApplicationGrid.horizontalSpacing, 72)
            }
        }
    }

    func testLargeCollectionsStayWithinViewportAndAllPagesPreserveOrder() {
        for size in [CGSize(width: 308, height: 936), CGSize(width: 456, height: 346), CGSize(width: 1024, height: 526)] {
            let grid = ReachableApplicationGrid(count: 200, size: size)
            let height = CGFloat(grid.rows) * ReachableApplicationGrid.cellHeight + CGFloat(grid.rows - 1) * ReachableApplicationGrid.verticalSpacing
            XCTAssertLessThanOrEqual(height + (grid.pages > 1 ? ReachableApplicationGrid.pageControlHeight : 0), size.height)
            XCTAssertGreaterThanOrEqual(grid.cellWidth, ReachableApplicationGrid.minimumCellWidth)
            for side in ToolbarSide.allCases {
                let indices = (0..<grid.pages).flatMap { page in
                    (0..<grid.columns).flatMap { grid.indices(inColumn: $0, side: side, page: page) }
                }
                XCTAssertEqual(indices.sorted(), Array(0..<200))
            }
        }
    }
}
