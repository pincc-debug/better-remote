import XCTest
@testable import RemoteFitCore

final class ConnectionDockTests: XCTestCase {
    private func decode(_ json: String) throws -> Preferences {
        try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    }

    func testDefaultIsKeepAndDoesNotNeedMonitoring() {
        var p = Preferences()
        XCTAssertEqual(p.connectionDockMode, .keep)
        // New installs enable 默认配置 · 分辨率规格, which alone needs monitoring.
        XCTAssertTrue(p.autoResolutionEnabled && p.hasAutomaticDefault)
        XCTAssertTrue(p.needsRemoteConnectionMonitoring)
        p.toolbarWhenConnected = false; p.autoRestoreOnDisconnect = false; p.autoResolutionEnabled = false
        XCTAssertFalse(p.needsRemoteConnectionMonitoring)
        p.connectionDockMode = .autoHide
        XCTAssertTrue(p.needsRemoteConnectionMonitoring)
    }

    func testLegacyToggleMigratesToAlwaysShow() throws {
        XCTAssertEqual(try decode("{\"autoShowDockOnConnect\":true}").connectionDockMode, .alwaysShow)
        XCTAssertEqual(try decode("{\"autoShowDockOnConnect\":false}").connectionDockMode, .keep)
        XCTAssertEqual(try decode("{}").connectionDockMode, .keep)
        // The new key wins over the old one, and unknown values fall back to the migration.
        XCTAssertEqual(try decode("{\"autoShowDockOnConnect\":true,\"connectionDockMode\":\"autoHide\"}").connectionDockMode, .autoHide)
        XCTAssertEqual(try decode("{\"autoShowDockOnConnect\":true,\"connectionDockMode\":\"bogus\"}").connectionDockMode, .alwaysShow)
    }

    func testRoundTripWritesOnlyTheNewKey() throws {
        var p = try decode("{\"autoShowDockOnConnect\":true}")
        p.connectionDockMode = .autoHide
        let data = try JSONEncoder().encode(p)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"connectionDockMode\":\"autoHide\""))
        XCTAssertFalse(text.contains("autoShowDockOnConnect"))
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), p)
    }

    func testTitlesAndTargets() {
        XCTAssertEqual(ConnectionDockMode.allCases.map(\.title), ["保持现状", "始终显示", "自动隐藏"])
        XCTAssertNil(ConnectionDockMode.keep.targetAutohide)
        XCTAssertEqual(ConnectionDockMode.alwaysShow.targetAutohide, false)
        XCTAssertEqual(ConnectionDockMode.autoHide.targetAutohide, true)
    }

    func testKeepNeverTouchesTheDock() {
        var s = ConnectionDockSession()
        XCTAssertFalse(s.needsDock(for: .keep))
        XCTAssertNil(s.apply(mode: .keep, current: true))
        XCTAssertNil(s.apply(mode: .keep, current: false))
        XCTAssertFalse(s.owesRestore)
    }

    /// The 0.8.145 bug: an always-shown Dock must stay shown with 始终显示 (no write, nothing to restore).
    func testAlwaysShowLeavesAnAlreadyShownDockAlone() {
        var s = ConnectionDockSession()
        XCTAssertNil(s.apply(mode: .alwaysShow, current: false))
        XCTAssertFalse(s.owesRestore)
        XCTAssertNil(s.restore(current: false))
    }

    func testAlwaysShowOnAutoHiddenDockRestoresOnDisconnect() {
        var s = ConnectionDockSession()
        XCTAssertEqual(s.apply(mode: .alwaysShow, current: true), false)
        XCTAssertEqual(s.originalAutohide, true)
        // A second pass in the same session (e.g. coalesced sync) changes nothing.
        XCTAssertNil(s.apply(mode: .alwaysShow, current: false))
        XCTAssertEqual(s.restore(current: false), true)
        XCTAssertFalse(s.owesRestore)
        XCTAssertNil(s.restore(current: true))
    }

    func testAutoHideOnShownDockRestoresOnDisconnect() {
        var s = ConnectionDockSession()
        XCTAssertEqual(s.apply(mode: .autoHide, current: false), true)
        XCTAssertEqual(s.restore(current: true), false)
    }

    func testRestoreSkipsWriteWhenUserAlreadyPutItBack() {
        var s = ConnectionDockSession()
        XCTAssertEqual(s.apply(mode: .autoHide, current: false), true)
        XCTAssertNil(s.restore(current: false))
        XCTAssertFalse(s.owesRestore)
    }

    func testModeChangesMidSessionKeepTheOriginal() {
        var s = ConnectionDockSession()
        XCTAssertEqual(s.apply(mode: .autoHide, current: false), true)
        // 自动隐藏 → 始终显示 equals the user's own value: give it back, nothing owed.
        XCTAssertEqual(s.apply(mode: .alwaysShow, current: true), false)
        XCTAssertFalse(s.owesRestore)

        var t = ConnectionDockSession(originalAutohide: false)
        // Switching to 保持现状 while connected gives back the original right away.
        XCTAssertTrue(t.needsDock(for: .keep))
        XCTAssertEqual(t.apply(mode: .keep, current: true), false)
        XCTAssertFalse(t.owesRestore)
    }

    func testUserChangeDuringSessionIsReappliedOnlyWhenAsked() {
        var s = ConnectionDockSession()
        XCTAssertEqual(s.apply(mode: .alwaysShow, current: true), false)
        // The user flipped the Dock back to auto-hide during the session; disconnect still restores their original.
        XCTAssertNil(s.restore(current: true))
    }

    func testCrashRecoveryRoundTrip() throws {
        let s = ConnectionDockSession(originalAutohide: true)
        let decoded = try JSONDecoder().decode(ConnectionDockSession.self, from: JSONEncoder().encode(s))
        var recovered = decoded
        XCTAssertTrue(recovered.owesRestore)
        // Next launch, not connected: 保持现状 gives back the saved value.
        XCTAssertEqual(recovered.apply(mode: .keep, current: false), true)
        XCTAssertFalse(recovered.owesRestore)
    }
}

final class DockRefitTests: XCTestCase {
    // 1728×1117 screen in AX coordinates: menu bar 32 pt, an always-shown Dock takes 70 pt at the bottom.
    private let autoHidden = CGRect(x: 0, y: 32, width: 1728, height: 1085)
    private let dockShown = CGRect(x: 0, y: 32, width: 1728, height: 1015)
    private func window(_ number: Int, _ frame: CGRect, pid: Int32 = 100, layer: Int = 0) -> ScreenWindow {
        ScreenWindow(number: number, pid: pid, bounds: frame, layer: layer)
    }

    func testFilledWindowShrinksAboveAlwaysShownDock() {
        let moves = DockRefit.plan(windows: [window(1, autoHidden)], areas: [.init(old: autoHidden, new: dockShown)], excludingPID: 1)
        XCTAssertEqual(moves, [.init(window: window(1, autoHidden), target: dockShown)])
    }

    func testFilledWindowGrowsWhenDockAutoHides() {
        // Within the 铺满 tolerance still counts as filled.
        let nearly = CGRect(x: 2, y: 34, width: 1724, height: 1011)
        let moves = DockRefit.plan(windows: [window(1, nearly)], areas: [.init(old: dockShown, new: autoHidden)], excludingPID: 1)
        XCTAssertEqual(moves.map(\.target), [autoHidden])
    }

    func testUserArrangedWindowsStayPut() {
        let half = CGRect(x: 0, y: 32, width: 864, height: 1085)
        let small = CGRect(x: 200, y: 200, width: 800, height: 600)
        let moves = DockRefit.plan(windows: [window(1, half), window(2, small)], areas: [.init(old: autoHidden, new: dockShown)], excludingPID: 1)
        XCTAssertTrue(moves.isEmpty)
    }

    func testSkipsOwnFloatingAndUnchangedScreens() {
        let areas = [DockRefit.Area(old: autoHidden, new: dockShown)]
        XCTAssertTrue(DockRefit.plan(windows: [window(1, autoHidden, pid: 7)], areas: areas, excludingPID: 7).isEmpty)
        XCTAssertTrue(DockRefit.plan(windows: [window(1, autoHidden, layer: 3)], areas: areas, excludingPID: 7).isEmpty)
        // The Dock change has not landed yet (or only rounding moved): nothing moves.
        let same = CGRect(x: 0, y: 32, width: 1728, height: 1084.5)
        XCTAssertFalse(DockRefit.changed(.init(old: autoHidden, new: same)))
        XCTAssertTrue(DockRefit.plan(windows: [window(1, autoHidden)], areas: [.init(old: autoHidden, new: same)], excludingPID: 7).isEmpty)
    }

    func testEachScreenUsesItsOwnArea() {
        let external = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let areas = [DockRefit.Area(old: autoHidden, new: dockShown), DockRefit.Area(old: external, new: external)]
        let moves = DockRefit.plan(windows: [window(1, autoHidden), window(2, external)], areas: areas, excludingPID: 7)
        XCTAssertEqual(moves.map(\.window.number), [1])
        XCTAssertEqual(moves.map(\.target), [dockShown])
    }
}
