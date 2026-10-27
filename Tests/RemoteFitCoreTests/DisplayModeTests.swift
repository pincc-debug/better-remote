import XCTest
@testable import RemoteFitCore

final class DisplayModeTests: XCTestCase {
    let dimensions = Dimensions(1200, 540)
    func testPresetsKeepAspectAcrossTextSizes() {
        for preset in ScreenPreset.allCases {
            let sizes = DisplaySize.allCases.map { preset.dimensions($0) }
            XCTAssertLessThan(sizes[0].width, sizes[1].width)
            XCTAssertLessThan(sizes[1].width, sizes[2].width)
            for size in sizes { XCTAssertEqual(size.width * sizes[0].height, size.height * sizes[0].width) }
        }
    }
    func testRetinaReadbackRejectsLoDPI() {
        let retina = DisplayMode(width: 1200, height: 540, pixelWidth: 2400, pixelHeight: 1080, refresh: 60)
        let loDPI = DisplayMode(width: 1200, height: 540, pixelWidth: 1200, pixelHeight: 540, refresh: 60)
        XCTAssertFalse(retina.matches(loDPI))
    }
}

final class RestoreTests: XCTestCase {
    func display(_ id: UInt32, uuid: String?, key: String, main: Bool = false, x: Int32 = 0, y: Int32 = 0) -> DisplayState {
        .init(id: id, uuid: uuid, hardwareKey: key, physical: true, main: main, x: x, y: y,
              mirror: 0, mode: .init(width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refresh: 60))
    }
    func testUUIDSurvivesDisplayIDChanges() throws {
        let saved = [display(1, uuid: "A", key: "one", main: true), display(2, uuid: "B", key: "two", y: -720)]
        let live = [display(11, uuid: "A", key: "one"), display(22, uuid: "B", key: "two")]
        let result = try RestorePlan.targets(saved: saved, live: live)
        XCTAssertEqual(result.map(\.id), [11, 22]); XCTAssertEqual(result[1].y, -720); XCTAssertTrue(result[0].main)
    }
    func testUniqueHardwareFallbackWhenUUIDUnavailable() throws {
        let result = try RestorePlan.targets(saved: [display(1, uuid: "A", key: "one", main: true)],
                                             live: [display(9, uuid: nil, key: "one")])
        XCTAssertEqual(result[0].id, 9)
    }
    func testAmbiguousHardwareIsNotGuessed() {
        XCTAssertThrowsError(try RestorePlan.targets(saved: [display(1, uuid: "A", key: "same", main: true)],
                                                     live: [display(3, uuid: nil, key: "same"), display(4, uuid: nil, key: "same")]))
    }
    func testUnpluggedMainReanchorsRemainingDisplay() throws {
        let result = try RestorePlan.targets(saved: [display(1, uuid: "A", key: "one", main: true),
                                                     display(2, uuid: "B", key: "two", x: -64, y: -720)],
                                             live: [display(8, uuid: "B", key: "two")])
        XCTAssertTrue(result[0].main); XCTAssertEqual(result[0].x, 0); XCTAssertEqual(result[0].y, 0)
    }
    func testHeadlessRestoreIsDeferredNotAnError() throws {
        let saved = [display(1, uuid: "A", key: "one", main: true)]
        var virtual = display(50, uuid: "V", key: "virt", main: true); virtual.physical = false
        XCTAssertEqual(try RestorePlan.outcome(saved: saved, live: []), .deferred)
        XCTAssertEqual(try RestorePlan.outcome(saved: saved, live: [virtual]), .deferred)
        XCTAssertEqual(try RestorePlan.outcome(saved: [], live: [virtual]), .deferred)
    }
    func testMonitorReturnRestoresSavedLayout() throws {
        let saved = [display(1, uuid: "A", key: "one", main: true)]
        guard case .restore(let targets) = try RestorePlan.outcome(saved: saved, live: [display(7, uuid: "A", key: "one")]) else { return XCTFail() }
        XCTAssertEqual(targets.map(\.id), [7]); XCTAssertTrue(targets[0].main)
    }
    func testDifferentMonitorOrHeadlessSnapshotJustReleasesVirtual() throws {
        let live = [display(9, uuid: "Z", key: "other")]
        XCTAssertEqual(try RestorePlan.outcome(saved: [display(1, uuid: "A", key: "one", main: true)], live: live), .release)
        XCTAssertEqual(try RestorePlan.outcome(saved: [], live: live), .release)
    }
    func testMissingAllOriginalDisplaysKeepsRecoveryPending() {
        XCTAssertThrowsError(try RestorePlan.targets(saved: [display(1, uuid: "A", key: "one", main: true)], live: []))
    }
    func testRestoreDriftDetectsHiDPISwitchWithSamePixels() {
        let oneX = DisplayMode(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refresh: 60, modeID: 10)
        let hiDPI = DisplayMode(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refresh: 60, modeID: 20)
        let looksLike1080 = DisplayMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refresh: 60)
        XCTAssertFalse(oneX.matches(hiDPI)); XCTAssertFalse(oneX.matches(looksLike1080))
        XCTAssertFalse(oneX.matches(DisplayMode(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refresh: 30)))
        XCTAssertTrue(oneX.matches(DisplayMode(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refresh: 59.94, modeID: 99)))
        var target = display(3, uuid: "R", key: "redmi", main: true); target.mode = oneX
        var live = target; live.mode = hiDPI
        XCTAssertEqual(RestoreDrift.drifted(targets: [target], live: [live]).map(\.id), [3])
        XCTAssertTrue(RestoreDrift.drifted(targets: [target], live: [target]).isEmpty)
        var skipped = target; skipped.skipMode = true
        XCTAssertTrue(RestoreDrift.drifted(targets: [skipped], live: [live]).isEmpty)
        XCTAssertTrue(RestoreDrift.drifted(targets: [target], live: []).isEmpty)
    }
    func testRestoreDriftChecksEveryDisplayOnItsOwnMode() {
        let builtin2x = DisplayMode(width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refresh: 120)
        let ext1x = DisplayMode(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refresh: 60)
        let ext2x = DisplayMode(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refresh: 60)
        var a = display(1, uuid: "B", key: "builtin", main: true); a.mode = builtin2x
        var b = display(2, uuid: "E1", key: "ext1", x: 1512); b.mode = ext1x
        var c = display(3, uuid: "E2", key: "ext2", x: 4072); c.mode = ext2x
        let targets = [a, b, c]
        XCTAssertTrue(RestoreDrift.drifted(targets: targets, live: targets).isEmpty)
        // Same point size, scale swapped between the two externals: both must be flagged.
        var b2 = b; b2.mode = ext2x; var c2 = c; c2.mode = ext1x
        XCTAssertEqual(RestoreDrift.drifted(targets: targets, live: [a, b2, c2]).map(\.id), [2, 3])
        // Refresh drift on built-in only.
        var a2 = a; a2.mode.refresh = 60
        XCTAssertEqual(RestoreDrift.drifted(targets: targets, live: [a2, b, c]).map(\.id), [1])
        // Main display and arrangement drift.
        var a3 = a; a3.main = false; var b3 = b; b3.main = true
        XCTAssertEqual(RestoreDrift.drifted(targets: targets, live: [a3, b3, c]).map(\.id), [1, 2])
        var c3 = c; c3.x = -2560
        XCTAssertEqual(RestoreDrift.drifted(targets: targets, live: [a, b, c3]).map(\.id), [3])
        // Matched per display id, not list order.
        XCTAssertTrue(RestoreDrift.drifted(targets: targets, live: [c, a, b]).isEmpty)
    }
}
