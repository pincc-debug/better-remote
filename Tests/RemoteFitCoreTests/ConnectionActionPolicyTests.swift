import XCTest
@testable import RemoteFitCore

final class ConnectionActionPolicyTests: XCTestCase {
    func testToolbarWaitsForDisplayWorkAndExpandsOnceWhenReady() {
        var toolbar = ConnectionToolbarPolicy()
        var resolution = AutomaticResolutionPolicy()
        toolbar.setEnabled(true)
        resolution.setEnabled(true)
        toolbar.connectionChanged(true)
        resolution.connectionChanged(true)
        XCTAssertEqual(resolution.nextAction(busy: false), .apply)
        XCTAssertFalse(toolbar.takeAction(busy: true))
        resolution.applied(success: true)
        XCTAssertNil(resolution.nextAction(busy: false))
        XCTAssertTrue(toolbar.takeAction(busy: false))
        XCTAssertFalse(toolbar.takeAction(busy: false))
    }
    func testToolbarWithoutResolutionAutomationDoesNotNeedExtraDelay() {
        var toolbar = ConnectionToolbarPolicy()
        toolbar.setEnabled(true)
        toolbar.connectionChanged(true)
        XCTAssertTrue(toolbar.takeAction(busy: false))
    }
    func testDisconnectAndDisablingCancelPendingExpansion() {
        var toolbar = ConnectionToolbarPolicy()
        toolbar.setEnabled(true)
        toolbar.connectionChanged(true)
        XCTAssertFalse(toolbar.takeAction(busy: true))
        toolbar.connectionChanged(false)
        XCTAssertFalse(toolbar.takeAction(busy: false))
        toolbar.connectionChanged(true)
        toolbar.setEnabled(false)
        XCTAssertFalse(toolbar.takeAction(busy: false))
        toolbar.setEnabled(true)
        XCTAssertTrue(toolbar.takeAction(busy: false))
    }
    func testLegacyDockSettingIsDiscardedAndNewSettingsRoundTrip() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data("{\"autoShowDockEnabled\":true,\"floatingSwitcherEnabled\":false}".utf8))
        XCTAssertTrue(preferences.toolbarWhenConnected)
        XCTAssertFalse(preferences.toolbarWhenDisconnected)
        preferences.toolbarWhenConnected = false
        preferences.toolbarWhenDisconnected = false
        preferences.autoRestoreOnDisconnect = false
        preferences.autoResolutionEnabled = false
        XCTAssertFalse(preferences.needsRemoteConnectionMonitoring)
        let data = try JSONEncoder().encode(preferences)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"autoShowDockEnabled\""))
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), preferences)
    }
    func testDisconnectionCanRestoreWithoutConnectionResolutionSwitch() {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(false)
        policy.restoreOnDisconnect = true
        policy.connectionChanged(true)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        XCTAssertNil(policy.nextAction(busy: false))
    }
    func testDockDefaultsOffAndOnlyRunsOncePerConnectionWhenEnabled() throws {
        let migrated = try JSONDecoder().decode(Preferences.self, from: Data("{\"autoShowDockEnabled\":true}".utf8))
        XCTAssertEqual(migrated.connectionDockMode, .keep)
        var policy = ConnectionDockPolicy()
        policy.connectionChanged(true)
        XCTAssertFalse(policy.takeAction(busy: false))
        policy.setEnabled(true)
        XCTAssertFalse(policy.takeAction(busy: true))
        XCTAssertTrue(policy.takeAction(busy: false))
        XCTAssertFalse(policy.takeAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertFalse(policy.takeAction(busy: false))
        policy.connectionChanged(true)
        XCTAssertTrue(policy.takeAction(busy: false))
    }
    func testDisabledDockAndDisconnectedSessionCancelPendingAction() {
        var policy = ConnectionDockPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        policy.connectionChanged(false)
        XCTAssertFalse(policy.takeAction(busy: false))
        policy.connectionChanged(true)
        policy.setEnabled(false)
        XCTAssertFalse(policy.takeAction(busy: false))
    }

}
