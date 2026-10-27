import XCTest
@testable import RemoteFitCore

final class InputLatencyTests: XCTestCase {
    func testWorkspaceCheckBacksOffWhenIdleAndResetsOnChange() {
        var s = WorkspaceCheckSchedule()
        XCTAssertEqual(s.interval, WorkspaceCheckSchedule.active)
        for _ in 0..<(WorkspaceCheckSchedule.idleAfter - 1) { s.unchanged() }
        XCTAssertEqual(s.interval, WorkspaceCheckSchedule.active)
        s.unchanged()
        XCTAssertEqual(s.interval, WorkspaceCheckSchedule.idle)
        s.changed()
        XCTAssertEqual(s.interval, WorkspaceCheckSchedule.active)
    }

    func testWorkspaceCheckPausesAfterAppLaunchThenRunsFast() {
        var s = WorkspaceCheckSchedule()
        for _ in 0..<20 { s.unchanged() }
        s.pause(now: 100)
        XCTAssertTrue(s.isPaused(now: 100.5))
        XCTAssertTrue(s.isPaused(now: 101.4))
        XCTAssertFalse(s.isPaused(now: 101.6))
        XCTAssertEqual(s.interval, WorkspaceCheckSchedule.active)
    }

    func testReplayedTapUsesCurrentPointerWithinTolerance() {
        let start = CGPoint(x: 100, y: 100)
        XCTAssertEqual(TouchPressDecision.replayPoint(start: start, current: CGPoint(x: 105, y: 103)), CGPoint(x: 105, y: 103))
        XCTAssertEqual(TouchPressDecision.replayPoint(start: start, current: start), start)
        XCTAssertNil(TouchPressDecision.replayPoint(start: start, current: CGPoint(x: 300, y: 100)))
    }
    func testTouchScrollingKeepsRemoteDetectionAliveWithoutAutomaticResolution() {
        var preferences = Preferences()
        preferences.autoResolutionEnabled = false
        preferences.toolbarWhenConnected = false
        preferences.toolbarWhenDisconnected = false
        preferences.autoFillWindowsOnRemote = false
        preferences.autoRestoreOnDisconnect = false
        preferences.uuTouchScrollEnabled = false
        XCTAssertFalse(preferences.needsRemoteConnectionMonitoring)
        preferences.uuTouchScrollEnabled = true
        XCTAssertTrue(preferences.needsRemoteConnectionMonitoring)
    }

}
