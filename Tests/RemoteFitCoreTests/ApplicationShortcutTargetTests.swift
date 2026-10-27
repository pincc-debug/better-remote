import XCTest
@testable import RemoteFitCore

final class ApplicationShortcutTargetTests: XCTestCase {
    func testRemoteClickActivatingToolbarPreservesPreviousApp() {
        XCTAssertEqual(ApplicationShortcutTarget.resolve(frontmost: 1, ownPID: 1, frontmostIsRegular: false,
                                                         recent: [20, 30], liveRegularPIDs: [20, 30], visibleWindowPIDs: [20, 30]), 20)
    }
    func testRemoteHelperAndMomentaryMissingFrontPreservePreviousApp() {
        for front: Int32? in [99, nil] {
            XCTAssertEqual(ApplicationShortcutTarget.resolve(frontmost: front, ownPID: 1, frontmostIsRegular: false,
                                                             recent: [20, 30], liveRegularPIDs: [20, 30], visibleWindowPIDs: [20, 30]), 20)
        }
    }
    func testRealApplicationSwitchDoesNotKeepOldConfiguredApplication() {
        XCTAssertEqual(ApplicationShortcutTarget.resolve(frontmost: 30, ownPID: 1, frontmostIsRegular: true,
                                                         recent: [20], liveRegularPIDs: [20, 30], visibleWindowPIDs: [20, 30]), 30)
    }
    func testTerminatedApplicationIsNeverReturned() {
        XCTAssertEqual(ApplicationShortcutTarget.resolve(frontmost: 1, ownPID: 1, frontmostIsRegular: false,
                                                         recent: [20, 30], liveRegularPIDs: [30], visibleWindowPIDs: [30]), 30)
        XCTAssertNil(ApplicationShortcutTarget.resolve(frontmost: nil, ownPID: 1, frontmostIsRegular: false,
                                                      recent: [20], liveRegularPIDs: [], visibleWindowPIDs: []))
    }
    func testClosingLastWindowHidesEntryEvenIfApplicationKeepsRunning() {
        for front: Int32? in [20, 1] {
            XCTAssertNil(ApplicationShortcutTarget.resolve(frontmost: front, ownPID: 1, frontmostIsRegular: front == 20,
                                                          recent: [20, 30], liveRegularPIDs: [20, 30], visibleWindowPIDs: [30]))
        }
    }
    func testRemainingOrReopenedWindowKeepsEntry() {
        XCTAssertEqual(ApplicationShortcutTarget.resolve(frontmost: 1, ownPID: 1, frontmostIsRegular: false,
                                                         recent: [20], liveRegularPIDs: [20], visibleWindowPIDs: [20]), 20)
    }

}
