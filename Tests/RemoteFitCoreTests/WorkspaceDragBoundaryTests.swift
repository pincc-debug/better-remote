import XCTest
@testable import RemoteFitCore

final class WorkspaceDragBoundaryTests: XCTestCase {
    func testLeftResizeStopsAtLeftToolbarAndStillAllowsShrinking() {
        let area = CGRect(x: 160, y: 30, width: 1120, height: 690)
        let window = CGRect(x: 200, y: 100, width: 600, height: 400)
        let start = CGPoint(x: 202, y: 200)
        let bounded = WorkspaceDragBoundary.location(CGPoint(x: 0, y: 220), start: start, window: window, area: area, kind: .resizeLeft)
        XCTAssertEqual(bounded, CGPoint(x: 162, y: 220))
        let shrink = CGPoint(x: 400, y: 220)
        XCTAssertEqual(WorkspaceDragBoundary.location(shrink, start: start, window: window, area: area, kind: .resizeLeft), shrink)
    }
    private let area = CGRect(x: 0, y: 30, width: 1130, height: 690)
    private let window = CGRect(x: 200, y: 100, width: 600, height: 400)
    private let start = CGPoint(x: 450, y: 110)

    func testLargeSingleDragStopsWindowRightEdgeAtToolbar() {
        let cursor = WorkspaceDragBoundary.location(CGPoint(x: 1400, y: 110), start: start, window: window, area: area, kind: .move)
        XCTAssertEqual(window.maxX + cursor.x - start.x, area.maxX)
        XCTAssertEqual(cursor.y, 110)
    }

    func testMovingAwayFromBoundaryIsImmediateWithoutStickyOffset() {
        _ = WorkspaceDragBoundary.location(CGPoint(x: 1800, y: 110), start: start, window: window, area: area, kind: .move)
        let back = CGPoint(x: 700, y: 140)
        XCTAssertEqual(WorkspaceDragBoundary.location(back, start: start, window: window, area: area, kind: .move), back)
    }

    func testMovingRespectsLeftTopAndBottomEdges() {
        let topLeft = WorkspaceDragBoundary.location(CGPoint(x: -100, y: -100), start: start, window: window, area: area, kind: .move)
        XCTAssertEqual(window.minX + topLeft.x - start.x, area.minX)
        XCTAssertEqual(window.minY + topLeft.y - start.y, area.minY)
        let bottom = WorkspaceDragBoundary.location(CGPoint(x: 450, y: 2000), start: start, window: window, area: area, kind: .move)
        XCTAssertEqual(window.maxY + bottom.y - start.y, area.maxY)
    }

    func testRightResizeKeepsVerticalGestureAndCanShrink() {
        let edge = CGPoint(x: 800, y: 300)
        let bounded = WorkspaceDragBoundary.location(CGPoint(x: 1800, y: 600), start: edge, window: window, area: area, kind: .resizeRight)
        XCTAssertEqual(bounded, CGPoint(x: 1130, y: 600))
        let shrink = CGPoint(x: 500, y: 600)
        XCTAssertEqual(WorkspaceDragBoundary.location(shrink, start: edge, window: window, area: area, kind: .resizeRight), shrink)
    }

    func testNegativeDisplayCoordinates() {
        let offset = CGFloat(-1920)
        let bounds = area.offsetBy(dx: offset, dy: -900)
        let frame = window.offsetBy(dx: offset, dy: -900)
        let cursor = WorkspaceDragBoundary.location(CGPoint(x: 100, y: -790), start: CGPoint(x: start.x + offset, y: start.y - 900), window: frame, area: bounds, kind: .move)
        XCTAssertEqual(cursor.x, 780 + offset)
        XCTAssertEqual(cursor.y, -790)
    }

    func testOversizedWindowDoesNotInvertHorizontalConstraint() {
        let large = CGRect(x: 0, y: 30, width: 1500, height: 800)
        let cursor = WorkspaceDragBoundary.location(CGPoint(x: 900, y: 200), start: start, window: large, area: area, kind: .move)
        XCTAssertEqual(large.maxX + cursor.x - start.x, area.maxX)
        XCTAssertEqual(cursor.y, 200)
    }
}
