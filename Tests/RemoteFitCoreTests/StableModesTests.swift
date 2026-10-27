import XCTest
@testable import RemoteFitCore

final class StableModesTests: XCTestCase {
    let oneX = DisplayMode(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refresh: 60)
    let hiDPI = DisplayMode(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refresh: 60)
    let builtinMode = DisplayMode(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 120)
    func builtin() -> DisplayState {
        .init(id: 1, uuid: "B", hardwareKey: "b", physical: true, main: true, x: 0, y: 0, mirror: 0, mode: builtinMode)
    }
    func ext(_ m: DisplayMode, x: Int32 = -1056, y: Int32 = -2160) -> DisplayState {
        .init(id: 2, uuid: "E", hardwareKey: "redmi", physical: true, main: false, x: x, y: y, mirror: 0, mode: m)
    }

    /// 10:48 log: live external already moved to upper-right (1728,-1440) before our snapshot.
    /// The stored centred-above 1x layout must win: mode AND origin.
    func testConnectTimeMoveIsCorrectedToStoredLayout() {
        var s = StableModes()
        let real = [builtin(), ext(oneX)]
        XCTAssertTrue(s.record(baseline: real, live: real))
        let (states, fixed) = s.corrected([builtin(), ext(oneX, x: 1728, y: -1440)])
        XCTAssertEqual(fixed, [2])
        let e = states.first { $0.id == 2 }!
        XCTAssertTrue(e.mode.matches(oneX)); XCTAssertEqual(e.x, -1056); XCTAssertEqual(e.y, -2160)
        XCTAssertTrue(states.first { $0.id == 1 }!.main)
    }
    func testLayoutChangedInsideWindowIsNotRecorded() {
        var s = StableModes()
        let real = [builtin(), ext(oneX)]
        s.record(baseline: real, live: real)
        XCTAssertFalse(s.record(baseline: real, live: [builtin(), ext(hiDPI, x: -1186, y: -1440)]))
        XCTAssertFalse(s.record(baseline: real, live: [builtin(), ext(oneX, x: 1728, y: -1440)]))
        XCTAssertTrue(s.corrected(real).fixed.isEmpty)
    }
    func testDeliberateChangeReplacesStoredLayout() {
        var s = StableModes()
        s.record(baseline: [builtin(), ext(oneX)], live: [builtin(), ext(oneX)])
        let moved = [builtin(), ext(hiDPI, x: 1728, y: -1440)]
        XCTAssertTrue(s.record(baseline: moved, live: moved))
        XCTAssertTrue(s.corrected(moved).fixed.isEmpty)
        XCTAssertFalse(s.record(baseline: moved, live: moved))
    }
    func testLayoutsAreKeptPerMonitorSet() {
        var s = StableModes()
        s.record(baseline: [builtin(), ext(oneX)], live: [builtin(), ext(oneX)])
        var lidClosed = ext(hiDPI, x: 0, y: 0); lidClosed.main = true
        s.record(baseline: [lidClosed], live: [lidClosed])
        XCTAssertEqual(s.layouts.count, 2)
        XCTAssertTrue(s.corrected([builtin(), ext(oneX)]).fixed.isEmpty)
        var drifted = lidClosed; drifted.mode = oneX
        XCTAssertTrue(s.corrected([drifted]).states[0].mode.matches(hiDPI))
    }
    func testVirtualOrUnknownSetIsLeftAlone() {
        var s = StableModes()
        var v = ext(hiDPI); v.physical = false; v.id = 9
        XCTAssertFalse(s.record(baseline: [builtin(), v], live: [builtin(), v]))
        XCTAssertTrue(s.corrected([builtin(), ext(oneX)]).fixed.isEmpty)
    }
    func testMismatchListsExactFields() {
        var t = ext(oneX); t.x = -1183
        var a = t; a.x = -3840
        XCTAssertEqual(StableModes.mismatches(target: t, actual: a), ["origin -3840,-2160 != -1183,-2160"])
        a.mode = hiDPI
        XCTAssertEqual(StableModes.mismatches(target: t, actual: a).count, 2)
        XCTAssertTrue(StableModes.mismatches(target: t, actual: t).isEmpty)
    }
}
