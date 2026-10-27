import XCTest
@testable import RemoteFitCore

final class DeviceConfigurationTests: XCTestCase {
    func testNewDeviceCopiesDefaultsOnce() throws {
        var preferences = Preferences()
        preferences.uuTouchScrollEnabled = false
        let defaults = preferences.configuration(for: nil)
        XCTAssertEqual(preferences.configuration(for: "unknown"), defaults)
        preferences.remember(.init(id: "uu:window:Phone", name: "Phone"))
        XCTAssertEqual(preferences.remoteDevices[0].configuration, defaults)
        preferences.uuTouchScrollEnabled = true
        XCTAssertFalse(preferences.configuration(for: "uu:window:Phone").uuTouchScrollEnabled)
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.configuration(for: "uu:window:Phone"), defaults)
    }

    func testIndependentProfilePersistsAcrossDefaultChanges() throws {
        var preferences = Preferences()
        let id = "uu:window:Computer"
        preferences.remember(.init(id: id, name: "Computer"))
        var computer = preferences.configuration(for: nil)
        computer.uuTouchScrollEnabled = false
        computer.uuScrollSpeedPercent = 100
        computer.autoFillWindowsOnRemote = true
        computer.connectionDockMode = .keep
        computer.toolbarWhenConnected = false
        computer.toolbarSide = .left
        preferences.setConfiguration(computer, for: id)
        preferences.uuTouchScrollEnabled = true
        preferences.uuScrollSpeedPercent = 25
        preferences.toolbarWhenConnected = true
        preferences.toolbarSide = .right
        preferences = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        preferences.remember(.init(id: id, name: "Computer"))
        XCTAssertEqual(preferences.configuration(for: id), computer)
        XCTAssertTrue(preferences.configuration(for: "uu:window:Phone").uuTouchScrollEnabled)
        XCTAssertEqual(preferences.configuration(for: id), computer)
    }

    func testLegacyResolutionBecomesCompleteIndependentProfile() throws {
        var preferences = Preferences()
        preferences.customPresets = CustomPreset.factorySpecs()
        let preset = try XCTUnwrap(preferences.customPresets.first)
        preferences.autoResolutionEnabled = true
        preferences.defaultResolutionEnabled = false
        preferences.uuTouchScrollEnabled = true
        preferences.toolbarWhenConnected = false
        preferences.toolbarSide = .left
        preferences.remoteDevices = [.init(id: "uu:window:Phone", name: "Phone", presetID: preset.id)]
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        let profile = try XCTUnwrap(restored.remoteDevices[0].configuration)
        XCTAssertTrue(profile.autoResolutionEnabled)
        XCTAssertEqual(profile.uuTouchScrollEnabled, Preferences().uuTouchScrollEnabled)
        XCTAssertEqual(profile.uuScrollSpeedPercent, Preferences().uuScrollSpeedPercent)
        XCTAssertEqual(profile.autoFillWindowsOnRemote, Preferences().autoFillWindowsOnRemote)
        XCTAssertEqual(profile.connectionDockMode, Preferences().connectionDockMode)
        XCTAssertEqual(profile.toolbarWhenConnected, Preferences().toolbarWhenConnected)
        XCTAssertEqual(profile.toolbarSide, Preferences().toolbarSide)
        XCTAssertEqual(restored.automaticPreset(for: "uu:window:Phone")?.id, preset.id)
        XCTAssertNil(restored.automaticPreset(for: nil))
    }

    func testDeviceResolutionOverridesDisabledDefaultAndDoesNotLeak() throws {
        var preferences = Preferences()
        preferences.customPresets = CustomPreset.factorySpecs()
        let preset = try XCTUnwrap(preferences.customPresets.first)
        preferences.autoResolutionEnabled = false
        preferences.remoteDevices = [.init(id: "uu:window:Phone", name: "Phone")]
        var profile = preferences.configuration(for: nil)
        profile.autoResolutionEnabled = true
        profile.autoResolutionPresetID = preset.id
        preferences.setConfiguration(profile, for: "uu:window:Phone")
        XCTAssertEqual(preferences.automaticPreset(for: "uu:window:Phone")?.id, preset.id)
        XCTAssertFalse(preferences.configuration(for: nil).autoResolutionEnabled)
        XCTAssertFalse(preferences.configuration(for: "unknown").autoResolutionEnabled)
        profile.autoResolutionEnabled = false
        preferences.setConfiguration(profile, for: "uu:window:Phone")
        XCTAssertNil(preferences.automaticPreset(for: "uu:window:Phone"))
    }
    func testDisabledDeviceNeverFallsBackAndRetainsSavedConfiguration() throws {
        var preferences = Preferences()
        let id = "uu:window:Computer"
        preferences.uuTouchScrollEnabled = true
        preferences.uuScrollSpeedPercent = 10
        preferences.autoResolutionEnabled = true
        preferences.autoFillWindowsOnRemote = true
        preferences.remoteDevices = [.init(id: id, name: "Computer")]
        var saved = preferences.configuration(for: nil)
        saved.uuScrollSpeedPercent = 25
        preferences.setConfiguration(saved, for: id)
        preferences.remoteDevices[0].configurationEnabled = false
        preferences = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        let inactive = preferences.effectiveConfiguration(for: id)
        XCTAssertFalse(inactive.autoResolutionEnabled)
        XCTAssertFalse(inactive.autoRestoreOnDisconnect)
        XCTAssertFalse(inactive.uuTouchScrollEnabled)
        XCTAssertEqual(inactive.uuScrollSpeedPercent, 100)
        XCTAssertFalse(inactive.autoFillWindowsOnRemote)
        XCTAssertEqual(inactive.connectionDockMode, .keep)
        XCTAssertEqual(inactive.toolbarWhenConnected, preferences.toolbarWhenDisconnected)
        XCTAssertEqual(preferences.configuration(for: id), saved)
        XCTAssertNil(preferences.automaticPreset(for: id))
        XCTAssertFalse(preferences.effectiveConfiguration(for: id).uuTouchScrollEnabled)
        preferences.remoteDevices[0].configurationEnabled = true
        XCTAssertEqual(preferences.effectiveConfiguration(for: id), saved)
    }

    func testLegacyDeviceMasterSwitchDefaultsOn() throws {
        let device = try JSONDecoder().decode(RemoteDevice.self, from: Data(#"{"id":"uu:window:Phone","name":"Phone"}"#.utf8))
        XCTAssertTrue(device.appliesConfiguration)
    }

    func testMasterOffRestoresOnlyAutomationOwnedResolution() {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.applied(success: true)
        policy.suspendConfiguration()
        XCTAssertNil(policy.nextAction(busy: true))
        XCTAssertEqual(policy.nextAction(busy: false), .restore)
        policy.restored(success: true)
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testMasterOffPreservesManualResolutionAndHandlesInFlightApply() {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.suspendConfiguration()
        XCTAssertNil(policy.nextAction(busy: true))
        policy.applied(success: true)
        XCTAssertEqual(policy.nextAction(busy: false), .restore)

        policy.setEnabled(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.applied(success: true)
        policy.manualAdjustment()
        policy.suspendConfiguration()
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        XCTAssertNil(policy.nextAction(busy: false))
    }

    func testCustomNameNeverChangesUUIdentityOrOriginalModel() throws {
        var preferences = Preferences()
        let original = RemoteDevice(id: "uu:window:vivoV2545A", name: "vivoV2545A")
        preferences.remember(original)
        preferences.renameDevice(original.id, to: "我的折叠手机")
        preferences.remember(original)
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.remoteDevices.count, 1)
        XCTAssertEqual(restored.remoteDevices[0].id, original.id)
        XCTAssertEqual(restored.remoteDevices[0].name, "vivoV2545A")
        XCTAssertEqual(restored.remoteDevices[0].displayName, "我的折叠手机")
        preferences.renameDevice(original.id, to: "  ")
        XCTAssertEqual(preferences.remoteDevices[0].displayName, "vivoV2545A")
    }

    func testOldInheritedDevicesBecomeIndependentSnapshotsOnUpgrade() throws {
        var preferences = Preferences()
        preferences.uuScrollSpeedPercent = 25
        preferences.remoteDevices = [.init(id: "uu:window:Phone", name: "Phone")]
        preferences = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        preferences.uuScrollSpeedPercent = 100
        XCTAssertEqual(preferences.configuration(for: "uu:window:Phone").uuScrollSpeedPercent, 25)
    }

    func testNoResolutionMeansNoDisconnectRestoreButKeepsOtherFeatures() {
        var preferences = Preferences()
        preferences.uuTouchScrollEnabled = true
        preferences.remember(.init(id: "uu:window:Phone", name: "Phone"))
        var configuration = preferences.configuration(for: "uu:window:Phone")
        configuration.selectResolution(nil)
        configuration.autoRestoreOnDisconnect = true
        preferences.setConfiguration(configuration, for: "uu:window:Phone")
        let effective = preferences.effectiveConfiguration(for: "uu:window:Phone")
        XCTAssertFalse(effective.autoResolutionEnabled)
        XCTAssertFalse(effective.autoRestoreOnDisconnect)
        XCTAssertTrue(effective.uuTouchScrollEnabled)
        configuration.selectResolution(preferences.customPresets.first?.id)
        preferences.setConfiguration(configuration, for: "uu:window:Phone")
        XCTAssertTrue(preferences.effectiveConfiguration(for: "uu:window:Phone").autoRestoreOnDisconnect)
    }

    func testNewTemplatesAndDevicesKeepSingleFingerScrollOff() throws {
        var preferences = Preferences()
        XCTAssertFalse(preferences.uuTouchScrollEnabled)
        preferences.remember(.init(id: "uu:window:New", name: "New"))
        XCTAssertFalse(preferences.configuration(for: "uu:window:New").uuTouchScrollEnabled)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"uuTouchScrollEnabled":true}"#.utf8))
        XCTAssertTrue(legacy.uuTouchScrollEnabled)
    }

}
