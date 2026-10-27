import XCTest
@testable import RemoteFitCore

final class AutomaticResolutionPreferenceTests: XCTestCase {
    func testFirstEnableChoosesFirstSavedSpec() {
        var preferences = Preferences()
        preferences.customPresets = [.init(id: "first", name: "第一项", width: 1400, height: 630),
                                     .init(id: "second", name: "第二项", width: 630, height: 1400)]
        preferences.setAutomaticResolutionEnabled(true)
        XCTAssertTrue(preferences.autoResolutionEnabled)
        XCTAssertEqual(preferences.autoResolutionPresetID, "first")
    }

    func testDisableAndReloadRetainPreviousDefault() throws {
        var preferences = Preferences()
        preferences.customPresets = [.init(id: "first", name: "第一项", width: 1400, height: 630),
                                     .init(id: "second", name: "第二项", width: 630, height: 1400)]
        preferences.autoResolutionPresetID = "second"
        preferences.setAutomaticResolutionEnabled(false)
        var decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(decoded.autoResolutionEnabled)
        XCTAssertEqual(decoded.autoResolutionPresetID, "second")
        decoded.setAutomaticResolutionEnabled(true)
        XCTAssertEqual(decoded.autoResolutionPresetID, "second")
    }

    func testMissingDefaultFallsBackAndEmptyListDoesNotInventSpec() {
        var preferences = Preferences()
        preferences.autoResolutionPresetID = "deleted"
        preferences.setAutomaticResolutionEnabled(true)
        XCTAssertEqual(preferences.autoResolutionPresetID, preferences.customPresets.first?.id)
        preferences.customPresets = []
        preferences.setAutomaticResolutionEnabled(true)
        XCTAssertNil(preferences.autoResolutionPresetID)
        XCTAssertFalse(preferences.hasAutomaticDefault)
    }
}
