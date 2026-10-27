import XCTest
@testable import RemoteFitCore

final class AutomaticResolutionTests: XCTestCase {
    private let uuPath = "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"
    private let tdPath = "/Applications/ToDesk.app/Contents/Helpers/ToDesk_Session.app/Contents/MacOS/ToDesk_Session"
    private let tdService = "/Applications/ToDesk.app/Contents/MacOS/ToDesk_Service"

    func testUURequiresItsConnectedAssertionRatherThanResidentProcess() {
        let resident = RemotePowerAssertion(executable: "/Applications/UURemote.app/Contents/MacOS/UURemote", type: "PreventUserIdleSystemSleep", name: "UURemote Disable Idle System Sleep", level: 255)
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([resident]))
        var active = RemotePowerAssertion(executable: uuPath, type: "PreventUserIdleDisplaySleep", name: "idleDisplaySleepDisabled", level: 255)
        XCTAssertTrue(RemoteSessionEvidence.uuConnected([resident, active]))
        active.level = 0
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
        active.level = 255; active.executable = "/tmp/UURemoteServer"
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
        active.executable = uuPath; active.name = "Wake Up Display"
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
    }

    func testUU442DisplaySleepAssertionCountsAsConnected() {
        let resident = RemotePowerAssertion(executable: "/Applications/UURemote.app/Contents/MacOS/UURemote", type: "PreventUserIdleSystemSleep", name: "UURemote Disable Idle System Sleep", level: 255)
        let wake = RemotePowerAssertion(executable: uuPath, type: "UserIsActive", name: "Wake Up Display", level: 255)
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([resident, wake]))
        var active = RemotePowerAssertion(executable: uuPath, type: "PreventUserIdleDisplaySleep", name: "UURemote Disable Display Sleep", level: 255)
        XCTAssertTrue(RemoteSessionEvidence.uuConnected([resident, wake, active]))
        active.type = "PreventUserIdleSystemSleep"
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
        active.type = "PreventUserIdleDisplaySleep"; active.executable = "/tmp/UURemoteServer"
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
        active.executable = uuPath; active.level = 0
        XCTAssertFalse(RemoteSessionEvidence.uuConnected([active]))
    }

    func testToDeskNeedsBothRealSessionAndMatchingPowerAssertion() {
        let assertion = RemotePowerAssertion(executable: tdService, type: "NoDisplaySleepAssertion", name: "Preventing display sleep for app", level: 255)
        XCTAssertTrue(RemoteSessionEvidence.toDeskConnected(processes: [tdPath], assertions: [assertion]))
        XCTAssertFalse(RemoteSessionEvidence.toDeskConnected(processes: [tdPath + "_Proxy"], assertions: [assertion]))
        XCTAssertFalse(RemoteSessionEvidence.toDeskConnected(processes: [tdPath], assertions: []))
        var other = assertion; other.executable = "/Applications/Other.app/Contents/MacOS/Other"
        XCTAssertFalse(RemoteSessionEvidence.toDeskConnected(processes: [tdPath], assertions: [other]))
    }

    func testConnectionDebouncesAndOnlyTriggersOnce() {
        var stability = RemoteSessionStability()
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 0))
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 1))
        XCTAssertEqual(stability.observe(.init(active: [.uu]), at: 2), .connected)
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 40))
        XCTAssertTrue(stability.isConnected)
    }

    func testTransientSignalDoesNotSwitchAndDisconnectNeedsOnePointFiveSeconds() {
        var stability = RemoteSessionStability()
        _ = stability.observe(.init(active: [.uu]), at: 0)
        _ = stability.observe(.init(), at: 1)
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 2))
        XCTAssertEqual(stability.observe(.init(active: [.uu]), at: 4), .connected)
        XCTAssertNil(stability.observe(.init(), at: 5))
        XCTAssertNil(stability.observe(.init(), at: 6.4))
        XCTAssertEqual(stability.observe(.init(), at: 6.5), .disconnected)
    }

    func testUnreadableConnectedProviderDoesNotRestoreAndRecoveryRestartsTimer() {
        var stability = RemoteSessionStability()
        _ = stability.observe(.init(active: [.uu]), at: 0)
        _ = stability.observe(.init(active: [.uu]), at: 2)
        XCTAssertNil(stability.observe(.init(unknown: [.uu]), at: 30))
        XCTAssertNil(stability.observe(.init(), at: 31))
        XCTAssertNil(stability.observe(.init(unknown: [.uu]), at: 34))
        XCTAssertNil(stability.observe(.init(), at: 35))
        XCTAssertEqual(stability.observe(.init(), at: 36.5), .disconnected)
    }

    func testSwitchingRemoteAppsDoesNotRestoreBetweenOverlappingConnections() {
        var stability = RemoteSessionStability()
        _ = stability.observe(.init(active: [.uu]), at: 0)
        _ = stability.observe(.init(active: [.uu]), at: 2)
        XCTAssertNil(stability.observe(.init(active: [.uu, .toDesk]), at: 3))
        XCTAssertNil(stability.observe(.init(active: [.toDesk]), at: 4))
        XCTAssertNil(stability.observe(.init(), at: 5))
        XCTAssertNil(stability.observe(.init(active: [.toDesk]), at: 8))
        XCTAssertTrue(stability.isConnected)
    }

    func testUnknownUnrelatedProviderDoesNotBlockConfirmedDisconnection() {
        var stability = RemoteSessionStability()
        _ = stability.observe(.init(active: [.uu]), at: 0)
        _ = stability.observe(.init(active: [.uu]), at: 2)
        _ = stability.observe(.init(unknown: [.toDesk]), at: 3)
        XCTAssertEqual(stability.observe(.init(unknown: [.toDesk]), at: 4.5), .disconnected)
    }

    func testDisabledFeatureAndBusyEngineDoNotConsumeConnection() {
        var policy = AutomaticResolutionPolicy()
        policy.connectionChanged(true)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.setEnabled(true)
        XCTAssertNil(policy.nextAction(busy: true))
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testDisconnectDuringApplyQueuesRestoreAfterCompletion() {
        var policy = connectedPolicy()
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.connectionChanged(false)
        XCTAssertNil(policy.nextAction(busy: true))
        policy.applied(success: true)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        policy.restored(success: true)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testManualAdjustmentDuringConnectionStillRestoresOriginalScreen() {
        var policy = connectedPolicy()
        _ = policy.nextAction(busy: false)
        policy.applied(success: true)
        policy.manualAdjustment()
        XCTAssertTrue(policy.ownsResolution)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
    }

    func testExplicitRestoreDoesNotReapplyDefaultButDisconnectStillRestoresDesktop() {
        var policy = connectedPolicy()
        _ = policy.nextAction(busy: false)
        policy.applied(success: true)
        policy.manualOverride()
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
    }

    func testReconnectDuringRestoreQueuesNewApply() {
        var policy = connectedPolicy()
        _ = policy.nextAction(busy: false)
        policy.applied(success: true)
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        policy.connectionChanged(true)
        XCTAssertNil(policy.nextAction(busy: true))
        policy.restored(success: true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
    }

    func testFailedApplyAndRestoreAreNotRetriedForever() {
        var policy = connectedPolicy()
        _ = policy.nextAction(busy: false)
        policy.applied(success: false)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.applied(success: true)
        policy.connectionChanged(false)
        _ = policy.nextAction(busy: false)
        policy.restored(success: false)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testDisconnectRestoresDesktopEvenWhenNoAutomaticApplyWasNeeded() {
        var policy = connectedPolicy()
        policy.manualOverride()
        policy.manualAdjustment()
        XCTAssertFalse(policy.ownsResolution)
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        policy.restored(success: true)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testDisablingConnectionSwitchKeepsIndependentDisconnectRestore() {
        var policy = connectedPolicy()
        policy.setEnabled(false)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
    }

    func testPreferencesMigrateDisabledAndPersistDefaultIndependently() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(old.autoResolutionEnabled)
        XCTAssertNil(old.autoResolutionPresetID)
        var preferences = old
        preferences.autoResolutionPresetID = preferences.customPresets.last?.id
        preferences.selectedCustomID = preferences.customPresets.first?.id
        preferences.autoResolutionEnabled = true
        let loaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(loaded, preferences)
        XCTAssertNotEqual(loaded.autoResolutionPresetID, loaded.selectedCustomID)
    }

    func testMissingDefaultDoesNotDisableDeviceMatching() throws {
        var preferences = Preferences()
        preferences.autoResolutionPresetID = "deleted-preset"
        preferences.autoResolutionEnabled = true
        let loaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(loaded.autoResolutionEnabled)
        XCTAssertNil(loaded.autoResolutionPresetID)
    }

    func testKeepingResolutionSkipsRestoreButStillAppliesOnNextConnection() throws {
        var policy = AutomaticResolutionPolicy()
        policy.restoreOnDisconnect = false
        policy.setEnabled(true)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.applied(success: true)
        policy.connectionChanged(false)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        XCTAssertTrue(Preferences().autoRestoreOnDisconnect)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.autoRestoreOnDisconnect)
        var off = Preferences(); off.autoRestoreOnDisconnect = false
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(off)).autoRestoreOnDisconnect)
    }

    private func connectedPolicy() -> AutomaticResolutionPolicy {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        return policy
    }
}
