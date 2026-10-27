import XCTest
@testable import RemoteFitCore

final class RemoteDeviceTests: XCTestCase {
    private let phone = RemoteDevice(id: "uu:window:手机", name: "手机")
    private let tablet = RemoteDevice(id: "uu:window:平板", name: "平板")

    func testWindowParserAcceptsOnlyActiveControlRows() {
        XCTAssertEqual(UUWindowDeviceParser.device(in: ["手机", "远程控制", "连接时长 00:01:20"]), phone)
        XCTAssertEqual(UUWindowDeviceParser.device(in: ["手机 远程控制 连接时长 00:01:20"]), phone)
        XCTAssertNil(UUWindowDeviceParser.device(in: ["手机", "在线"]))
        XCTAssertNil(UUWindowDeviceParser.device(in: ["远程控制", "连接时长 00:01:20"]))
        XCTAssertNil(UUWindowDeviceParser.device(in: ["本机被控中", "远程控制"]))
    }

    func testRememberPersistsDeduplicatesRenamesAndUsesDefaultForBlankOrDeletedPreset() throws {
        var p = Preferences()
        p.customPresets = [.init(id: "default", name: "默认", width: 1200, height: 800),
                           .init(id: "phone", name: "手机", width: 800, height: 1200)]
        p.autoResolutionPresetID = "default"
        p.remoteDevices = [phone]
        XCTAssertNil(p.remoteDevices.first?.presetID)
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, "default")
        p.remoteDevices[0].presetID = "phone"
        p.remember(.init(id: phone.id, name: "新名称"))
        XCTAssertEqual(p.remoteDevices.count, 1)
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, "phone")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.remoteDevices[0].id, p.remoteDevices[0].id)
        XCTAssertEqual(decoded.remoteDevices[0].name, "新名称")
        XCTAssertEqual(decoded.remoteDevices[0].configuration?.autoResolutionPresetID, "phone")
        XCTAssertNil(decoded.remoteDevices[0].presetID)
        XCTAssertEqual(p.automaticPreset(for: nil)?.id, "default")
        p.customPresets.removeAll { $0.id == "phone" }
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, "default")
        let cleaned = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertNil(cleaned.remoteDevices[0].presetID)
        XCTAssertTrue(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).remoteDevices.isEmpty)
    }

    func testDeviceSwitchOffUsesDefaultAndKeepsCollectedDevicesAndRules() throws {
        var p = Preferences()
        p.customPresets = [.init(id: "default", name: "默认", width: 1200, height: 800),
                           .init(id: "phone", name: "手机", width: 800, height: 1200)]
        p.autoResolutionPresetID = "default"
        p.remoteDevices = [phone]
        p.remoteDevices[0].presetID = "phone"
        p.deviceResolutionEnabled = false
        p.remember(tablet)
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, "default")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertFalse(decoded.deviceResolutionEnabled)
        XCTAssertEqual(decoded.remoteDevices.count, 2)
        XCTAssertEqual(decoded.remoteDevices[0].configuration?.autoResolutionPresetID, "phone")
        XCTAssertFalse(decoded.remoteDevices[0].configuration?.autoResolutionEnabled ?? true)
        p.deviceResolutionEnabled = true
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, "phone")
    }

    func testDefaultOffLeavesUnknownAndUnconfiguredDevicesUnchanged() throws {
        var p = Preferences()
        p.autoResolutionEnabled = true
        p.defaultResolutionEnabled = false
        p.remoteDevices = [phone]
        XCTAssertNil(p.automaticPreset(for: nil))
        XCTAssertNil(p.automaticPreset(for: phone.id))
        p.remoteDevices[0].presetID = p.customPresets[0].id
        XCTAssertEqual(p.automaticPreset(for: phone.id)?.id, p.customPresets[0].id)
        p.deviceResolutionEnabled = false
        XCTAssertNil(p.automaticPreset(for: phone.id))
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertFalse(decoded.defaultResolutionEnabled)
        XCTAssertTrue(decoded.autoResolutionEnabled)
    }

    func testWindowIdentityPreservesUniquePreviouslyCollectedProfile() {
        var p = Preferences()
        p.remoteDevices = [.init(id: "uu:old-id", name: "手机", presetID: "configured")]
        p.remember(phone)
        XCTAssertEqual(p.remoteDevices.count, 1)
        XCTAssertEqual(p.remoteDevices[0].id, phone.id)
        XCTAssertEqual(p.remoteDevices[0].presetID, "configured")
    }

    func testDeletedDeviceStaysRemovedUntilNextConnection() {
        var p = Preferences()
        var collection = RemoteDeviceCollection()
        collection.remember(phone, in: &p)
        p.remoteDevices[0].presetID = "configured"
        collection.remove(phone.id, from: &p)
        collection.remember(phone, in: &p)
        XCTAssertTrue(p.remoteDevices.isEmpty)
        collection.disconnected()
        collection.remember(phone, in: &p)
        XCTAssertEqual(p.remoteDevices.count, 1)
        XCTAssertNil(p.remoteDevices[0].presetID)
    }

    func testOfflineDeletionIsFreshOnNextConnection() {
        var preferences = Preferences()
        var collection = RemoteDeviceCollection()
        collection.remember(phone, in: &preferences)
        preferences.renameDevice(phone.id, to: "旧名字")
        preferences.remoteDevices[0].configurationEnabled = false
        collection.remove(phone.id, from: &preferences, suppressRediscovery: false)
        XCTAssertFalse(collection.isRemoved(phone.id))
        collection.remember(phone, in: &preferences)
        XCTAssertEqual(preferences.remoteDevices.count, 1)
        XCTAssertEqual(preferences.remoteDevices[0].displayName, phone.name)
        XCTAssertTrue(preferences.remoteDevices[0].appliesConfiguration)
        XCTAssertEqual(preferences.remoteDevices[0].configuration, preferences.configuration(for: nil))
    }

    func testControllerHandoffCannotOverrideManualChoice() {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.controllerChanged()
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.manualAdjustment()
        policy.controllerChanged()
        XCTAssertNil(policy.nextAction(busy: false))
        policy.connectionChanged(false)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
    }

    /// Nil → device (late identify after connect) must be able to queue apply.
    func testLateIdentifyTriggersApply() {
        var policy = AutomaticResolutionPolicy()
        policy.setEnabled(true)
        policy.connectionChanged(true)
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
        policy.applied(success: false) // no preset yet while device still unknown
        XCTAssertNil(policy.nextAction(busy: false))
        policy.controllerChanged() // device appeared
        XCTAssertEqual(policy.nextAction(busy: false), .apply)
    }
}
