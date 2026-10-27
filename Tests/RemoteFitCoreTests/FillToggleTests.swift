import XCTest
@testable import RemoteFitCore

final class FillToggleTests: XCTestCase {
    let area = CGRect(x: 0, y: 38, width: 1440, height: 820)
    let key = FillToggle.Key(pid: 42, window: 7)

    func testFilledDetectionTolerance() {
        XCTAssertTrue(FillToggle.isFilled(area, in: area))
        XCTAssertTrue(FillToggle.isFilled(area.insetBy(dx: 3, dy: 3), in: area))
        XCTAssertTrue(FillToggle.isFilled(CGRect(x: 0, y: 36, width: 1446, height: 824), in: area))
        XCTAssertFalse(FillToggle.isFilled(area.insetBy(dx: 10, dy: 0), in: area))
        XCTAssertFalse(FillToggle.isFilled(CGRect(x: 0, y: 38, width: 1440, height: 700), in: area))
    }
    func testFillSavesThenRestoresAndClears() {
        var t = FillToggle()
        let original = CGRect(x: 100, y: 120, width: 800, height: 600)
        XCTAssertEqual(t.target(for: key, current: original, area: area), area)
        XCTAssertEqual(t.savedFrame(for: key), original)
        XCTAssertTrue(t.observe(key, frame: area, area: area))
        XCTAssertEqual(t.target(for: key, current: area, area: area), original)
        XCTAssertNil(t.savedFrame(for: key))
    }
    func testManuallyMaximizedFallsBackToCenteredTwoThirds() {
        var t = FillToggle()
        let target = t.target(for: key, current: area, area: area)
        XCTAssertEqual(target.width, 960); XCTAssertEqual(target.height, 547)
        XCTAssertEqual(target.midX, area.midX, accuracy: 1); XCTAssertEqual(target.midY, area.midY, accuracy: 1)
        XCTAssertEqual(t.target(for: nil, current: area, area: area), FillToggle.centered(in: area))
    }
    func testRestoreIsClampedAfterResolutionChange() {
        var t = FillToggle()
        _ = t.target(for: key, current: CGRect(x: 1800, y: 900, width: 1700, height: 500), area: CGRect(x: 0, y: 0, width: 3456, height: 2200))
        let restored = t.target(for: key, current: area, area: area)
        XCTAssertEqual(restored, CGRect(x: 0, y: 358, width: 1440, height: 500))
        XCTAssertTrue(area.contains(restored))
    }
    func testInvalidation() {
        var t = FillToggle()
        _ = t.target(for: key, current: CGRect(x: 50, y: 60, width: 500, height: 400), area: area)
        // Still animating towards filled: not yet confirmed, keep.
        t.observe(key, frame: CGRect(x: 50, y: 60, width: 900, height: 700), area: area)
        XCTAssertNotNil(t.savedFrame(for: key))
        t.observe(key, frame: area, area: area)
        // User resizes away from filled: drop.
        XCTAssertFalse(t.observe(key, frame: CGRect(x: 10, y: 60, width: 700, height: 500), area: area))
        XCTAssertNil(t.savedFrame(for: key))
        // Closed window: drop.
        _ = t.target(for: key, current: CGRect(x: 50, y: 60, width: 500, height: 400), area: area)
        t.observe(nil, frame: nil, area: nil, liveKeys: [])
        XCTAssertNil(t.savedFrame(for: key))
    }
}
