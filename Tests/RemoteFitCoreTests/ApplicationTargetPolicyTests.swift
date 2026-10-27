import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class ApplicationTargetPolicyTests: XCTestCase {
    func testTinyRemoteHelperAndTooltipAreNotApplicationWindows() {
        XCTAssertFalse(ApplicationTargetPolicy.isUsableWindow(CGRect(x: 1228, y: 905, width: 24, height: 32)))
        XCTAssertFalse(ApplicationTargetPolicy.isUsableWindow(CGRect(x: 300, y: 320, width: 66, height: 20)))
        XCTAssertTrue(ApplicationTargetPolicy.isUsableWindow(CGRect(x: -1200, y: 30, width: 1164, height: 1126)))
        XCTAssertTrue(ApplicationTargetPolicy.isUsableWindow(CGRect(x: 0, y: 0, width: 80, height: 60)))
        XCTAssertFalse(ApplicationTargetPolicy.isUsableWindow(.null))
    }

    func testInvalidFocusedHelperCannotReenterThroughHistoryOrBackgroundWindow() {
        // A remote app may own a normal window behind its focused tiny helper.
        XCTAssertEqual(ApplicationTargetPolicy.resolve(frontmost: 20, ownPID: 99,
            visibleWindowPIDs: [20, 10], recent: [20, 10], frontmostWindowUsable: false), 10)
    }

    func testRealRemoteClientWindowStillReceivesItsOwnActions() {
        XCTAssertEqual(ApplicationTargetPolicy.resolve(frontmost: 20, ownPID: 99,
            visibleWindowPIDs: [20, 10], recent: [10, 20], frontmostWindowUsable: true), 20)
    }

    func testOwnSettingsPreservePreviousVisibleApplication() {
        XCTAssertEqual(ApplicationTargetPolicy.resolve(frontmost: 99, ownPID: 99,
            visibleWindowPIDs: [99, 20, 10], recent: [10, 20], frontmostWindowUsable: nil), 10)
    }

    func testGoneOrInvisibleApplicationsAreSkippedAndVisibleOrderIsFallback() {
        XCTAssertEqual(ApplicationTargetPolicy.resolve(frontmost: 30, ownPID: 99,
            visibleWindowPIDs: [20, 10], recent: [30, 40], frontmostWindowUsable: nil), 20)
        XCTAssertNil(ApplicationTargetPolicy.resolve(frontmost: 20, ownPID: 99,
            visibleWindowPIDs: [99], recent: [20, 99], frontmostWindowUsable: false))
    }
}
