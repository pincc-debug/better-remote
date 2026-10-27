import XCTest
@testable import RemoteFitCore

final class DragScrollGestureTests: XCTestCase {
    func testSmallMovesStayClicksAndSwipeScrolls() {
        var g = DragScrollGesture(start: CGPoint(x: 100, y: 300), startOffset: 50)
        XCTAssertNil(g.drag(to: CGPoint(x: 104, y: 305), maxOffset: 500))
        XCTAssertNil(g.drag(to: CGPoint(x: 140, y: 310), maxOffset: 500), "mostly horizontal stays a click/drag")
        XCTAssertFalse(g.isScrolling)
        XCTAssertEqual(g.drag(to: CGPoint(x: 100, y: 400), maxOffset: 500), 150)
        XCTAssertTrue(g.isScrolling)
        XCTAssertEqual(g.drag(to: CGPoint(x: 100, y: 302), maxOffset: 500), 52, "once scrolling, small moves keep scrolling")
        XCTAssertEqual(g.drag(to: CGPoint(x: 100, y: 0), maxOffset: 500), 0)
        XCTAssertEqual(g.drag(to: CGPoint(x: 100, y: 2000), maxOffset: 500), 500)
    }
}
