import XCTest
@testable import RemoteFitCore

final class ToolbarPresenceTests: XCTestCase {
    private func decode(_ json: String) throws -> Preferences {
        try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
    }

    // MARK: Migration of 连接时展开 / 断开时收起

    func testMigrationMapsLegacyToolbarAutomation() throws {
        for expand in [true, false] {
            for manage in [true, false] {
                let p = try decode("{\"floatingSwitcherEnabled\":false,\"autoExpandToolbarOnConnect\":\(expand),\"autoManageToolbarOnDisconnect\":\(manage)}")
                XCTAssertEqual(p.toolbarWhenConnected, expand, "连接时展开 \(expand)")
                XCTAssertEqual(p.toolbarWhenDisconnected, !manage, "断开时收起 \(manage)")
            }
        }
    }

    func testMigrationOfCurrentUserSettings() throws {
        // 立品's saved file: master switch off, 连接时展开 on, 断开时收起 on.
        let p = try decode("{\"floatingSwitcherEnabled\":false,\"autoExpandToolbarOnConnect\":true,\"autoManageToolbarOnDisconnect\":true,\"toolbarSide\":\"right\"}")
        XCTAssertTrue(p.toolbarWhenConnected)
        XCTAssertFalse(p.toolbarWhenDisconnected)
        XCTAssertEqual(p.toolbarSide, .right)
    }

    func testMissingKeysUseNewDefaults() throws {
        let p = try decode("{}")
        XCTAssertTrue(p.toolbarWhenConnected)
        XCTAssertFalse(p.toolbarWhenDisconnected)
        XCTAssertFalse(p.autoFillWindowsOnRemote)
        XCTAssertEqual(Preferences().toolbarWhenConnected, true)
        XCTAssertEqual(Preferences().toolbarWhenDisconnected, false)
    }

    func testMalformedLegacyValuesDecodeSafely() throws {
        let p = try decode("{\"autoExpandToolbarOnConnect\":\"yes\",\"autoManageToolbarOnDisconnect\":3,\"toolbarWhenDisconnected\":null}")
        XCTAssertTrue(p.toolbarWhenConnected)
        XCTAssertFalse(p.toolbarWhenDisconnected)
    }

    func testNewKeysWinAndLegacyKeysAreNotWrittenBack() throws {
        let p = try decode("{\"autoExpandToolbarOnConnect\":true,\"autoManageToolbarOnDisconnect\":true,\"toolbarWhenConnected\":false,\"toolbarWhenDisconnected\":true,\"autoFillWindowsOnRemote\":true}")
        XCTAssertFalse(p.toolbarWhenConnected)
        XCTAssertTrue(p.toolbarWhenDisconnected)
        XCTAssertTrue(p.autoFillWindowsOnRemote)
        let encoded = try JSONEncoder().encode(p)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for legacy in ["floatingSwitcherEnabled", "autoExpandToolbarOnConnect", "autoManageToolbarOnDisconnect"] { XCTAssertNil(object[legacy]) }
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded), p)
    }

    // MARK: Connect / disconnect / 5 s grace

    private func prefs(connected: Bool, disconnected: Bool) -> Preferences {
        var p = Preferences(); p.toolbarWhenConnected = connected; p.toolbarWhenDisconnected = disconnected; return p
    }

    func testShowsFollowsTheSettingForTheContext() {
        let p = prefs(connected: true, disconnected: false)
        XCTAssertTrue(ToolbarPresence.shows(.connected, preferences: p))
        XCTAssertFalse(ToolbarPresence.shows(.disconnected, preferences: p))
        let q = prefs(connected: false, disconnected: true)
        XCTAssertFalse(ToolbarPresence.shows(.connected, preferences: q))
        XCTAssertTrue(ToolbarPresence.shows(.disconnected, preferences: q))
    }

    func testLaunchStartsDisconnected() {
        XCTAssertEqual(ToolbarPresence().context, .disconnected)
        XCTAssertNil(ToolbarPresence().delayUntilTick(at: 0))
    }

    func testConnectAppliesImmediately() {
        var state = ToolbarPresence()
        XCTAssertEqual(state.remoteChanged(connected: true, at: 10), .connected)
        XCTAssertEqual(state.context, .connected)
        XCTAssertNil(state.remoteChanged(connected: true, at: 11), "repeated connect changes nothing")
    }

    func testDisconnectWaitsFiveSeconds() {
        var state = ToolbarPresence()
        _ = state.remoteChanged(connected: true, at: 0)
        XCTAssertNil(state.remoteChanged(connected: false, at: 100))
        XCTAssertEqual(state.context, .connected)
        XCTAssertEqual(state.delayUntilTick(at: 100), 5)
        XCTAssertNil(state.tick(at: 104.9))
        XCTAssertEqual(state.tick(at: 105), .disconnected)
        XCTAssertEqual(state.context, .disconnected)
        XCTAssertNil(state.tick(at: 200))
        XCTAssertNil(state.delayUntilTick(at: 200))
    }

    func testReconnectInsideGraceIsAsIfNeverDisconnected() {
        var state = ToolbarPresence()
        _ = state.remoteChanged(connected: true, at: 0)
        XCTAssertNil(state.remoteChanged(connected: false, at: 50))
        XCTAssertNil(state.remoteChanged(connected: true, at: 53), "no re-apply, no flicker")
        XCTAssertNil(state.tick(at: 60))
        XCTAssertEqual(state.context, .connected)
        XCTAssertNil(state.delayUntilTick(at: 60))
    }

    func testSecondDisconnectDoesNotExtendGrace() {
        var state = ToolbarPresence()
        _ = state.remoteChanged(connected: true, at: 0)
        _ = state.remoteChanged(connected: false, at: 10)
        _ = state.remoteChanged(connected: false, at: 13)
        XCTAssertEqual(state.tick(at: 15), .disconnected)
    }

    func testDisconnectWhileAlreadyDisconnectedIsIgnored() {
        var state = ToolbarPresence()
        XCTAssertNil(state.remoteChanged(connected: false, at: 1))
        XCTAssertNil(state.delayUntilTick(at: 1))
    }

    func testReconnectAfterGraceAppliesConnectedAgain() {
        var state = ToolbarPresence()
        _ = state.remoteChanged(connected: true, at: 0)
        _ = state.remoteChanged(connected: false, at: 10)
        XCTAssertEqual(state.tick(at: 15), .disconnected)
        XCTAssertEqual(state.remoteChanged(connected: true, at: 20), .connected)
    }
}
