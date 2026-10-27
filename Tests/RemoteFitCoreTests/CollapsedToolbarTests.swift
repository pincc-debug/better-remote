import XCTest
@testable import RemoteFitCore

final class CollapsedToolbarTests: XCTestCase {
    func testOnlyNearbyEdgeExpandsAndOtherEdgesStayFixed() {
        let screen = CGRect(x: -1280, y: 33, width: 1280, height: 690)
        for side: ToolbarSide in [.left, .right] {
            let toolbar = CGRect(x: side == .right ? -80 : -1272, y: 33, width: 72, height: 690)
            for gap: CGFloat in [0, 8, 10, 10.1, 40, -1] {
                let window = CGRect(x: side == .right ? toolbar.minX - gap - 600 : toolbar.maxX + gap,
                                    y: 120, width: 600, height: 400)
                let result = WindowLayout.fillingCollapsedToolbar(window, toolbar: toolbar, screen: screen, side: side)
                if gap >= 0 && gap <= 10 {
                    XCTAssertEqual(result?.minY, window.minY)
                    XCTAssertEqual(result?.height, window.height)
                    XCTAssertEqual(side == .right ? result?.minX : result?.maxX, side == .right ? window.minX : window.maxX)
                    XCTAssertEqual(side == .right ? result?.maxX : result?.minX, side == .right ? screen.maxX : screen.minX)
                } else { XCTAssertNil(result) }
            }
        }
    }

    func testOtherScreensAndHorizontalToolbarDoNotChangeWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let toolbar = CGRect(x: 1120, y: 0, width: 72, height: 800)
        XCTAssertNil(WindowLayout.fillingCollapsedToolbar(CGRect(x: 0, y: 900, width: 1112, height: 200), toolbar: toolbar, screen: screen, side: .right))
        XCTAssertNil(WindowLayout.fillingCollapsedToolbar(CGRect(x: 0, y: 0, width: 1112, height: 700), toolbar: toolbar, screen: screen, side: .top))
    }
}
