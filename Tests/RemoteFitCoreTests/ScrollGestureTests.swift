import XCTest
@testable import RemoteFitCore

final class ScrollGestureTests: XCTestCase {
    func testSmallMovementIsTapAndLargerIsDrag() {
        XCTAssertTrue(ScrollGesture.isTap(from: (100, 100), to: (104, 103)))
        XCTAssertFalse(ScrollGesture.isTap(from: (100, 100), to: (100, 120)))
    }

    func testContentFollowsFinger() {
        var gesture = ScrollGesture()
        let up = gesture.record(dx: 0, dy: -30, at: 0)
        XCTAssertEqual(up.vertical, -30) // negative wheel scrolls page content upward
        let down = gesture.record(dx: 0, dy: 12, at: 0.016)
        XCTAssertEqual(down.vertical, 12)
    }

    func testFractionalMovementAccumulates() {
        var gesture = ScrollGesture()
        var total: Int32 = 0
        for i in 0..<10 { total += gesture.record(dx: 0, dy: -0.4, at: Double(i) * 0.01).vertical }
        XCTAssertEqual(total, -4)
    }

    func testVelocityUsesRecentSamplesOnly() {
        var gesture = ScrollGesture()
        _ = gesture.record(dx: 0, dy: -500, at: 0)
        _ = gesture.record(dx: 0, dy: -10, at: 1.0)
        _ = gesture.record(dx: 0, dy: -10, at: 1.05)
        let v = gesture.velocity(at: 1.05)
        XCTAssertEqual(v.dy, -400, accuracy: 1)
    }

    func testMomentumDecaysAndSlowReleaseHasNone() {
        let frames = ScrollGesture.momentum(velocity: (0, -1200))
        XCTAssertFalse(frames.isEmpty)
        XCTAssertEqual(frames[0].dy, -20, accuracy: 0.001)
        XCTAssertLessThan(abs(frames.last!.dy), abs(frames[0].dy))
        XCTAssertTrue(ScrollGesture.momentum(velocity: (0, -60)).isEmpty)
    }

    func testPressClassification() {
        XCTAssertEqual(TouchPressDecision.classify(elapsed: 0.1, distance: 2), .undecided)
        XCTAssertEqual(TouchPressDecision.classify(elapsed: 0.15, distance: 20), .scroll)
        XCTAssertEqual(TouchPressDecision.classify(elapsed: 0.45, distance: 3), .undecided)
        XCTAssertEqual(TouchPressDecision.classify(elapsed: 0.85, distance: 3), .hold)
        // Late move past slop is still scroll (not long-press drag).
        XCTAssertEqual(TouchPressDecision.classify(elapsed: 0.9, distance: 30), .scroll)
    }
}

final class TouchScrollPreferenceTests: XCTestCase {
    func testOffByDefaultAndPersists() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.uuTouchScrollEnabled)
        var enabled = legacy
        enabled.uuTouchScrollEnabled = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(enabled))
        XCTAssertTrue(decoded.uuTouchScrollEnabled)
    }
}
