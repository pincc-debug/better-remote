import XCTest
@testable import RemoteFitCore

final class WindowMaximizeSnapshotTests: XCTestCase {
    let original = CGRect(x: 432, y: 169, width: 864, height: 813)
    let maximized = CGRect(x: 0, y: 33, width: 1640, height: 1084)

    func testSecondClickRestoresBothPositionAndSize() {
        let snapshot = WindowMaximizeSnapshot(original: original, maximized: maximized)
        XCTAssertEqual(snapshot.restoration(from: maximized), original)
    }

    func testNoOpMaximizeCannotBecomeRestoreRecord() {
        let snapshot = WindowMaximizeSnapshot(original: maximized, maximized: maximized)
        XCTAssertNil(snapshot.restoration(from: maximized))
    }

    func testManualRestoreInvalidatesOldSnapshotBeforeNextMaximize() {
        let previous = WindowMaximizeSnapshot(original: CGRect(x: 40, y: 60, width: 1000, height: 900), maximized: maximized)
        XCTAssertNil(previous.restoration(from: original))
        let next = WindowMaximizeSnapshot(original: original, maximized: maximized)
        XCTAssertEqual(next.restoration(from: maximized), original)
    }

    func testMovingMaximizedWindowAlsoInvalidatesRecord() {
        let snapshot = WindowMaximizeSnapshot(original: original, maximized: maximized)
        XCTAssertNil(snapshot.restoration(from: maximized.offsetBy(dx: 100, dy: 0)))
    }

    func testParallelModeInitialFillCanBeRestoredWithoutFillingAgain() {
        let snapshot = WindowMaximizeSnapshot(original: original, maximized: maximized)
        let restored = snapshot.restoration(from: maximized)!
        XCTAssertEqual(WindowLayout.frame(restored, in: maximized, placement: .moveToScreen), original)
    }
}
