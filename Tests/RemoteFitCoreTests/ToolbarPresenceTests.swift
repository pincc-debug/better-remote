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
                XCTAssertEqual(p.toolbarWhenConnected, ToolbarVisibility.migratedConnected(expand), "连接时展开 \(expand)")
                XCTAssertEqual(p.toolbarWhenDisconnected, ToolbarVisibility.migratedDisconnected(!manage), "断开时收起 \(manage)")
            }
        }
    }

    func testMigrationOfCurrentUserSettings() throws {
        // 立品's saved file: master switch off, 连接时展开 on, 断开时收起 on.
        let p = try decode("{\"floatingSwitcherEnabled\":false,\"autoExpandToolbarOnConnect\":true,\"autoManageToolbarOnDisconnect\":true,\"toolbarSide\":\"right\"}")
        XCTAssertEqual(p.toolbarWhenConnected, .toolbar)
        XCTAssertEqual(p.toolbarWhenDisconnected, .hidden)
        XCTAssertEqual(p.toolbarSide, .right)
    }

    func testMissingKeysUseNewDefaults() throws {
        let p = try decode("{}")
        XCTAssertEqual(p.toolbarWhenConnected, .toolbar)
        XCTAssertEqual(p.toolbarWhenDisconnected, .hidden)
        XCTAssertFalse(p.autoFillWindowsOnRemote)
        XCTAssertEqual(Preferences().toolbarWhenConnected, .toolbar)
        XCTAssertEqual(Preferences().toolbarWhenDisconnected, .hidden)
    }

    func testMalformedLegacyValuesDecodeSafely() throws {
        let p = try decode("{\"autoExpandToolbarOnConnect\":\"yes\",\"autoManageToolbarOnDisconnect\":3,\"toolbarWhenDisconnected\":null}")
        XCTAssertEqual(p.toolbarWhenConnected, .toolbar)
        XCTAssertEqual(p.toolbarWhenDisconnected, .hidden)
    }

    func testNewKeysWinAndLegacyKeysAreNotWrittenBack() throws {
        let p = try decode("{\"autoExpandToolbarOnConnect\":true,\"autoManageToolbarOnDisconnect\":true,\"toolbarWhenConnected\":false,\"toolbarWhenDisconnected\":true,\"autoFillWindowsOnRemote\":true}")
        XCTAssertEqual(p.toolbarWhenConnected, .ball)
        XCTAssertEqual(p.toolbarWhenDisconnected, .toolbar)
        XCTAssertTrue(p.autoFillWindowsOnRemote)
        let encoded = try JSONEncoder().encode(p)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for legacy in ["floatingSwitcherEnabled", "autoExpandToolbarOnConnect", "autoManageToolbarOnDisconnect"] { XCTAssertNil(object[legacy]) }
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded), p)
    }

    // MARK: Connect / disconnect / 5 s grace

    private func prefs(connected: ToolbarVisibility, disconnected: ToolbarVisibility) -> Preferences {
        var p = Preferences(); p.toolbarWhenConnected = connected; p.toolbarWhenDisconnected = disconnected; return p
    }

    func testLevelFollowsTheSettingForTheContext() {
        let p = prefs(connected: .toolbar, disconnected: .hidden)
        XCTAssertEqual(ToolbarPresence.level(.connected, preferences: p), .toolbar)
        XCTAssertEqual(ToolbarPresence.level(.disconnected, preferences: p), .hidden)
        let q = prefs(connected: .ball, disconnected: .toolbar)
        XCTAssertEqual(ToolbarPresence.level(.connected, preferences: q), .ball)
        XCTAssertEqual(ToolbarPresence.level(.disconnected, preferences: q), .toolbar)
    }

    func testHiddenBecomesBallWhileVirtualResolutionIsOutstanding() {
        XCTAssertEqual(ToolbarPresence.surface(level: .hidden, virtualResolutionOutstanding: false), .hidden)
        XCTAssertEqual(ToolbarPresence.surface(level: .hidden, virtualResolutionOutstanding: true), .ball)
        XCTAssertEqual(ToolbarPresence.surface(level: .ball, virtualResolutionOutstanding: false), .ball)
        XCTAssertEqual(ToolbarPresence.surface(level: .ball, virtualResolutionOutstanding: true), .ball)
        XCTAssertEqual(ToolbarPresence.surface(level: .toolbar, virtualResolutionOutstanding: true), .toolbar)
    }

    func testConnectedOffMigratesToBallAndDisconnectedOffStaysHidden() throws {
        let p = try decode("{\"toolbarWhenConnected\":false,\"toolbarWhenDisconnected\":false}")
        XCTAssertEqual(p.toolbarWhenConnected, .ball)
        XCTAssertEqual(p.toolbarWhenDisconnected, .hidden)
        let encoded = try JSONEncoder().encode(p)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["toolbarWhenConnected"] as? String, "ball")
        XCTAssertEqual(object["toolbarWhenDisconnected"] as? String, "hidden")
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded).toolbarWhenConnected, .ball)
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
