import XCTest
@testable import RemoteFitCore

final class HoverTrackerTests: XCTestCase {
    func testTeleportAndTapNeverLeaveHover() {
        var t = HoverTracker<String>()
        // Touch tap: cursor appears on 粘贴, presses, releases.
        t.pointerMoved(to: CGPoint(x: 10, y: 100), over: "paste")
        XCTAssertNil(t.hoveredID)
        t.pointerMoved(to: CGPoint(x: 10, y: 100), over: "paste", buttonDown: true)
        t.reset()
        XCTAssertNil(t.hoveredID)
        // Next tap teleports far away onto 复制.
        t.pointerMoved(to: CGPoint(x: 10, y: 400), over: "copy")
        XCTAssertNil(t.hoveredID)
    }
    func testGenuineMovementHoversExactlyOneItem() {
        var t = HoverTracker<String>()
        t.pointerMoved(to: CGPoint(x: 10, y: 100), over: "paste")
        t.pointerMoved(to: CGPoint(x: 12, y: 104), over: "paste")
        XCTAssertEqual(t.hoveredID, "paste")
        t.pointerMoved(to: CGPoint(x: 12, y: 130), over: "copy")
        XCTAssertEqual(t.hoveredID, "copy")
        t.pointerMoved(to: CGPoint(x: 12, y: 500), over: "esc")
        XCTAssertNil(t.hoveredID, "a jump is a teleport")
    }
    func testPressScrollAndExitClear() {
        var t = HoverTracker<Int>()
        t.pointerMoved(to: .zero, over: 1); t.pointerMoved(to: CGPoint(x: 3, y: 0), over: 1)
        XCTAssertEqual(t.hoveredID, 1)
        t.pointerMoved(to: CGPoint(x: 4, y: 0), over: 1, buttonDown: true)
        XCTAssertNil(t.hoveredID)
        t.pointerMoved(to: CGPoint(x: 6, y: 0), over: 1)
        XCTAssertNil(t.hoveredID, "first sample after a press does not hover")
        t.pointerMoved(to: CGPoint(x: 8, y: 0), over: 1)
        XCTAssertEqual(t.hoveredID, 1)
        t.leave(2); XCTAssertEqual(t.hoveredID, 1)
        t.leave(1); XCTAssertNil(t.hoveredID)
    }
}
