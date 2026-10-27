import XCTest
@testable import RemoteFitCore

final class CustomPresetTests: XCTestCase {
    func testOldPreferencesRemainCompatible() throws {
        let old = Data(#"{"enabled":false,"preset":"tablet","size":"larger"}"#.utf8)
        let p = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(p.preset, .tablet); XCTAssertEqual(p.size, .larger)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        XCTAssertNil(encoded["enabled"])
        XCTAssertEqual(p.customPresets.map(\.id), CustomPreset.factorySpecs().map(\.id))
        XCTAssertTrue(p.seededFactorySpecs)
        XCTAssertNil(p.selectedCustomID)
        XCTAssertEqual(p.dimensions, Dimensions(896, 672))
    }

    func testFactorySpecsAreSeededOnce() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"preset":"phone"}"#.utf8))
        XCTAssertEqual(old.customPresets.count, CustomPreset.factorySpecs().count)
        var trimmed = old
        trimmed.customPresets.removeFirst()
        let roundtrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(trimmed))
        XCTAssertEqual(roundtrip.customPresets.count, CustomPreset.factorySpecs().count - 1)
    }
    func testCustomSelectionSurvivesSaveAndReload() throws {
        var p = Preferences()
        let custom = CustomPreset(name: "便携屏", width: 1480, height: 740)
        p.customPresets = [custom]; p.selectedCustomID = custom.id
        p.autoResolutionPresetID = nil // the default target points at a built-in spec this list no longer has
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(p, decoded); XCTAssertEqual(decoded.dimensions, Dimensions(1480, 740))
    }
    func testValidationRejectsInvalidAndOverflowInputs() {
        for value in [-1, 0, 511, 3841, Int.max] {
            XCTAssertThrowsError(try CustomPreset(name: "", width: value, height: 720).validate())
            XCTAssertThrowsError(try CustomPreset(name: "", width: 1280, height: value).validate())
        }
        XCTAssertNoThrow(try CustomPreset(name: "", width: 512, height: 3840).validate())
    }
    func testFontScalingDoesNotMutateSavedBaseSize() {
        let p = CustomPreset(name: "", width: 1920, height: 1080)
        XCTAssertEqual(p.dimensions(.larger), Dimensions(1632, 918))
        XCTAssertEqual(p.dimensions(.moreSpace), Dimensions(2304, 1296))
        XCTAssertEqual(p.dimensions(.standard), Dimensions(1920, 1080))
    }
    func testCustomScaleBoundsAreExplicit() {
        let small = CustomPreset(name: "", width: 512, height: 512)
        XCTAssertFalse(CustomPreset.isSupported(small.dimensions(.larger)))
        let large = CustomPreset(name: "", width: 3840, height: 2160)
        XCTAssertFalse(CustomPreset.isSupported(large.dimensions(.moreSpace)))
    }
    func testMissingCustomSelectionFallsBackToDefault() {
        var p = Preferences(); p.selectedCustomID = "deleted"
        XCTAssertEqual(p.dimensions, ScreenPreset.phone.dimensions(.standard))
    }
    func testInvalidStoredCustomIsNotApplied() throws {
        var p = Preferences()
        p.customPresets = [CustomPreset(id: "bad", name: "", width: Int.max, height: 720)]
        p.selectedCustomID = "bad"
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertTrue(decoded.customPresets.isEmpty)
        XCTAssertEqual(decoded.dimensions, ScreenPreset.phone.dimensions(.standard))
    }
}
