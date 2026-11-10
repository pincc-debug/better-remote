import XCTest
@testable import RemoteFitCore

final class DisplayCensusTests: XCTestCase {
    private let panelKey = "1552:41012:0:false"
    private let panelUUID = "78D18F0B-93D1-42BA-8491-9099E78687E2"
    private func mode(_ width: Int, _ height: Int, scale: Int = 2, refresh: Double = 60) -> DisplayMode {
        .init(width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refresh: refresh)
    }
    private func savedPanel() -> DisplayState {
        .init(id: 3, uuid: panelUUID, hardwareKey: panelKey, physical: true, main: true,
              x: 0, y: 0, mirror: 0, mode: mode(1920, 1080))
    }
    private func virtualSample(id: UInt32 = 108) -> DisplaySample {
        .init(id: id, uuid: "virtual", hardwareKey: "\(ActivationBase.ownVendor):1:1112670210:false",
              ownVirtual: true, main: true, x: 0, y: 0, mirror: 0, mode: mode(604, 1000), listedOnline: true)
    }
    /// The 2026-11-09 case: the panel is only a mirror behind the virtual display, with no current mode,
    /// and it is absent from CGGetOnlineDisplayList. A mode-based snapshot would defer restore.
    private func mirroredPanel(master: UInt32 = 108, listed: Bool = false) -> DisplaySample {
        .init(id: 3, uuid: panelUUID, hardwareKey: panelKey, ownVirtual: false, main: false,
              x: 0, y: 0, mirror: master, mode: nil, listedOnline: listed)
    }

    func testMirroredModelessPanelIsPhysicalAndRestoresTheSavedMode() throws {
        let samples = [virtualSample(), mirroredPanel()]
        let live = DisplayCensus.states(from: samples)
        let panel = try XCTUnwrap(live.first { $0.id == 3 })
        XCTAssertTrue(panel.physical)
        XCTAssertTrue(panel.skipMode)
        XCTAssertEqual(panel.mirror, 108)
        guard case .restore(let targets) = try RestorePlan.outcome(saved: [savedPanel()], live: live) else {
            return XCTFail(DisplayCensus.summary(samples))
        }
        XCTAssertEqual(targets.map(\.id), [3])
        XCTAssertEqual(targets[0].mode, mode(1920, 1080))
        XCTAssertEqual(targets[0].mirror, 0)
        let summary = DisplayCensus.summary(samples)
        XCTAssertTrue(summary.contains("physical=1"))
        XCTAssertTrue(summary.contains("modeless=1"))
        XCTAssertTrue(summary.contains("unlisted=1"))
    }

    func testVirtualDisplayAloneStillDefers() throws {
        let live = DisplayCensus.states(from: [virtualSample()])
        XCTAssertEqual(try RestorePlan.outcome(saved: [savedPanel()], live: live), .deferred)
    }

    func testVendorZeroGhostFromTheIdScanIsDropped() {
        let ghost = DisplaySample(id: 40, uuid: nil, hardwareKey: "0:0:0:false", ownVirtual: false,
                                  main: false, x: 0, y: 0, mirror: 0, mode: nil, listedOnline: false)
        XCTAssertFalse(DisplayCensus.isUsable(ghost))
        XCTAssertTrue(DisplayCensus.states(from: [ghost]).isEmpty)
        let listed = DisplaySample(id: 40, uuid: nil, hardwareKey: "0:0:0:false", ownVirtual: false,
                                   main: false, x: 0, y: 0, mirror: 0, mode: nil, listedOnline: true)
        XCTAssertTrue(DisplayCensus.isUsable(listed))
    }

    func testUnlistedPanelWithARealVendorCountsEvenWithoutAMirrorFlag() throws {
        var panel = mirroredPanel(master: 0, listed: false)
        panel.mode = nil
        let live = DisplayCensus.states(from: [virtualSample(), panel])
        guard case .restore = try RestorePlan.outcome(saved: [savedPanel()], live: live) else { return XCTFail() }
    }
}

final class NativeLayoutFallbackTests: XCTestCase {
    func testHiddenPanelUsesTheLastStableNativeMode() {
        let mode = DisplayMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refresh: 60)
        var panel = DisplayState(id: 3, uuid: "78D18F0B-93D1-42BA-8491-9099E78687E2", hardwareKey: "1552:41012:0:false",
                                  physical: true, main: true, x: 0, y: 0, mirror: 0, mode: mode)
        var stable = StableModes()
        XCTAssertTrue(stable.record(baseline: [panel], live: [panel]))
        panel.mode = .init(width: 0, height: 0, pixelWidth: 0, pixelHeight: 0, refresh: 0)
        panel.mirror = 108
        panel.skipMode = true
        let virtual = DisplayState(id: 108, uuid: "v", hardwareKey: "\(ActivationBase.ownVendor):1:1:false",
                                   physical: false, main: true, x: 0, y: 0, mirror: 0,
                                   mode: .init(width: 604, height: 1000, pixelWidth: 1208, pixelHeight: 2000, refresh: 60))
        let targets = NativeLayoutFallback.targets(live: [virtual, panel], stable: stable)
        XCTAssertEqual(targets?.map(\.id), [3])
        XCTAssertEqual(targets?.first?.mode, mode)
        XCTAssertEqual(targets?.first?.mirror, 0)
        XCTAssertNil(NativeLayoutFallback.targets(live: [virtual], stable: stable))
    }
}

final class RollbackModeTests: XCTestCase {
    private let portrait = Dimensions(604, 1000)
    private func source(_ mode: DisplayMode) -> DisplayState {
        .init(id: 106, uuid: "old", hardwareKey: "\(ActivationBase.ownVendor):1:1:false", physical: false,
              main: true, x: 0, y: 0, mirror: 0, mode: mode)
    }

    func testUnspecifiedRefreshStillMatchesThePreviousDesktopSize() throws {
        let live = DisplayMode(width: 604, height: 1000, pixelWidth: 1208, pixelHeight: 2000, refresh: 0)
        let selected = RollbackMode.selected(applied: nil, live: live, dimensions: portrait)
        XCTAssertEqual(selected?.width, 604)
        XCTAssertEqual(selected?.pixelHeight, 2000)
        XCTAssertEqual(selected?.refresh, 60)
        XCTAssertTrue(RollbackMode.compatible(try XCTUnwrap(selected), dimensions: portrait))
    }

    func testAppliedModeWinsWhenTheLiveModeDrifted() {
        let applied = DisplayMode(width: 604, height: 1000, pixelWidth: 1208, pixelHeight: 2000, refresh: 60)
        let live = DisplayMode(width: 800, height: 600, pixelWidth: 800, pixelHeight: 600, refresh: 0)
        XCTAssertEqual(RollbackMode.selected(applied: applied, live: live, dimensions: portrait), applied)
        XCTAssertNil(RollbackMode.selected(applied: nil, live: live, dimensions: portrait))
    }

    func testIncompatibleLiveModeLetsTheTransitionSynthesizeHiDPI() throws {
        let drifted = DisplayMode(width: 800, height: 600, pixelWidth: 1600, pixelHeight: 1200, refresh: 0)
        XCTAssertThrowsError(try DisplayTransition.targets(source: source(drifted), dimensions: portrait,
                                                            physical: [], selectedMode: drifted))
        let targets = try DisplayTransition.targets(source: source(drifted), dimensions: portrait,
                                                    physical: [], selectedMode: nil)
        XCTAssertEqual(targets[0].mode.width, 604)
        XCTAssertEqual(targets[0].mode.pixelWidth, 1208)
        XCTAssertEqual(targets[0].mode.refresh, 60)
    }

    func testRollbackVerificationAcceptsUnspecifiedRefresh() throws {
        let applied = DisplayMode(width: 604, height: 1000, pixelWidth: 1208, pixelHeight: 2000, refresh: 60)
        let targets = try DisplayTransition.targets(source: source(applied), dimensions: portrait,
                                                    physical: [], selectedMode: applied)
        var live = targets
        live[0].mode.refresh = 0
        XCTAssertFalse(DisplayTransition.matches(live, targets: targets, sourceID: 106))
        XCTAssertTrue(DisplayTransition.matches(live, targets: targets, sourceID: 106, tolerateUnspecifiedRefresh: true))
    }
}

final class DeviceToolbarMigrationTests: XCTestCase {
    func testStoredDeviceBoolOffBecomesBall() throws {
        let json = """
        {"id":"uu:window:Computer","name":"Computer","configuration":{"autoResolutionEnabled":true,"autoRestoreOnDisconnect":true,"uuTouchScrollEnabled":false,"uuScrollSpeedPercent":100,"autoFillWindowsOnRemote":false,"connectionDockMode":"keep","toolbarWhenConnected":false,"toolbarSide":"right"}}
        """
        let device = try JSONDecoder().decode(RemoteDevice.self, from: Data(json.utf8))
        XCTAssertEqual(device.configuration?.toolbarWhenConnected, .ball)
        let on = json.replacingOccurrences(of: "\"toolbarWhenConnected\":false", with: "\"toolbarWhenConnected\":\"toolbar\"")
        XCTAssertEqual(try JSONDecoder().decode(RemoteDevice.self, from: Data(on.utf8)).configuration?.toolbarWhenConnected, .toolbar)
    }
}
