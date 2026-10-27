import XCTest
@testable import RemoteFitCore

final class WindowPlacementTests: XCTestCase {
    private let area = CGRect(x: 0, y: 30, width: 1180, height: 1126)

    func testReportedChromeWidthIsReanchoredInsideRightEdge() throws {
        let target = CGRect(x: 590, y: 30, width: 590, height: 1126)
        let actual = CGRect(x: 590, y: 30, width: 626, height: 1126)
        let placed = try XCTUnwrap(WindowPlacement.constrainedFrame(actual, target: target, in: area))
        XCTAssertEqual(placed, CGRect(x: 554, y: 30, width: 626, height: 1126))
        XCTAssertTrue(area.contains(placed))
        XCTAssertFalse(WindowLayout.reached(actual, target: target, allowsSizeRounding: true))
    }

    func testLeftAndBottomSlotsKeepTheirIntendedEdges() throws {
        let left = CGRect(x: 0, y: 30, width: 590, height: 1126)
        XCTAssertEqual(WindowPlacement.constrainedFrame(CGRect(x: 0, y: 30, width: 626, height: 1126), target: left, in: area)?.minX, 0)
        let bottom = CGRect(x: 0, y: 593, width: 1180, height: 563)
        let result = try XCTUnwrap(WindowPlacement.constrainedFrame(CGRect(x: 0, y: 593, width: 1180, height: 600), target: bottom, in: area))
        XCTAssertEqual(result.maxY, area.maxY)
        XCTAssertEqual(result.minY, 556)
    }

    func testUnchangedFullWindowAndUnrelatedMovementAreNotSuccessfulSplits() {
        let target = CGRect(x: 590, y: 30, width: 590, height: 1126)
        XCTAssertNil(WindowPlacement.constrainedFrame(area, target: target, in: area))
        XCTAssertNil(WindowPlacement.constrainedFrame(CGRect(x: 100, y: 100, width: 626, height: 900), target: target, in: area))
        XCTAssertNil(WindowPlacement.constrainedFrame(CGRect(x: 590, y: 30, width: 1300, height: 1126), target: target, in: area))
        XCTAssertNil(WindowPlacement.constrainedFrame(CGRect(x: 590, y: 30, width: 626, height: 300), target: target, in: area))
        XCTAssertNil(WindowPlacement.constrainedFrame(target, target: target, in: area))
    }
}
