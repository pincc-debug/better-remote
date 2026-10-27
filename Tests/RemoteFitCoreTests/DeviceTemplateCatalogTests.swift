import XCTest
@testable import RemoteFitCore

final class DeviceTemplateCatalogTests: XCTestCase {
    func testBundledCatalogIncludesLatestScreensAndBrandHierarchy() throws {
        let catalog = try DeviceTemplateCatalog.bundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(catalog.entries.count, 42)
        XCTAssertEqual(Set(catalog.entries.map(\.id)).count, catalog.entries.count)
        let duo = try XCTUnwrap(catalog.entries.first { $0.modelName == "iPhone Duo" && $0.screenName == "内屏" })
        XCTAssertEqual(duo.preset.dimensions(.standard), Dimensions(1335, 939))
        let fold = try XCTUnwrap(catalog.entries.first { $0.modelName == "vivo X Fold6" && $0.screenName == "内屏" })
        XCTAssertEqual(fold.preset.dimensions(.standard), Dimensions(1156, 1252))
        let monitor = try XCTUnwrap(catalog.entries.first { $0.brandID == "generic" && $0.matches("24英寸") })
        XCTAssertEqual(monitor.preset.dimensions(.standard), Dimensions(1920, 1080))
        XCTAssertEqual(duo.categoryID, "foldable")
        XCTAssertEqual(duo.brandID, "apple")
        XCTAssertTrue(duo.matches("iphone duo"))
        XCTAssertNotNil(catalog.entries.first { $0.modelName.contains("X Fold6") })
        XCTAssertNotNil(catalog.entries.first { $0.modelName.contains("Find N6") })
        XCTAssertNotNil(catalog.entries.first { $0.modelName.contains("18 Pro Max") && $0.brandID == "xiaomi" })
        for entry in catalog.entries { XCTAssertNoThrow(try entry.preset.validate()) }
    }
    func testComputerCatalogHasOfficialModelsAndGenericSizes() throws {
        let catalog = try DeviceTemplateCatalog.bundled()
        let computers = catalog.entries.filter { $0.categoryID == "computer" }
        XCTAssertEqual(Set(computers.map(\.brandID)), ["apple", "lenovo", "dell", "generic"])
        let mac = try XCTUnwrap(computers.first { $0.modelName.contains("MacBook Pro 16") })
        XCTAssertEqual(mac.width, 3456)
        XCTAssertEqual(mac.height, 2234)
        XCTAssertTrue(computers.contains { $0.brandID == "generic" && $0.matches("14寸") })
        XCTAssertTrue(computers.contains { $0.brandID == "generic" && $0.matches("16寸") })
        XCTAssertEqual(computers.filter { $0.modelName.contains("XPS 13") }.count, 3)
    }
    func testInvalidOverrideIsReportedInsteadOfSilentlyUsingOtherData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("device-templates.json")
        try Data("{broken".utf8).write(to: path)
        XCTAssertThrowsError(try DeviceTemplateCatalog.load(overrideURL: path))
    }
    func testPresetScalePersistsIndependentlyOfOtherPresetsAndLegacySize() throws {
        var p = Preferences()
        let first = CustomPreset(id: "one", name: "手机", width: 1920, height: 1080, scalePercent: 120)
        let second = CustomPreset(id: "two", name: "平板", width: 2048, height: 1536, scalePercent: 90)
        p.customPresets = [first, second]
        p.autoResolutionPresetID = nil // the default target points at a built-in spec this list no longer has
        p.selectedCustomID = first.id
        p.size = .moreSpace
        XCTAssertEqual(p.dimensions, Dimensions(1600, 900))
        XCTAssertEqual(p.resolutionAdjustment.scalePercent, 120)
        p.selectedCustomID = second.id
        XCTAssertEqual(p.dimensions, Dimensions(2276, 1707))
        XCTAssertEqual(p.resolutionAdjustment.scalePercent, 90)
        let loaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(loaded, p)
        XCTAssertEqual(loaded.customPresets[0].scalePercent, 120)
        XCTAssertEqual(loaded.customPresets[1].scalePercent, 90)
    }
    func testOldPresetDefaultsToOneHundredPercentAndInvalidScaleIsRejected() throws {
        let p = try JSONDecoder().decode(CustomPreset.self, from: Data(#"{"id":"old","name":"原规格","width":1280,"height":720}"#.utf8))
        XCTAssertEqual(p.scalePercent, 100)
        XCTAssertEqual(p.dimensions(.standard), Dimensions(1280, 720))
        XCTAssertNil(p.settingScale(0))
        XCTAssertNil(p.settingScale(200))
        XCTAssertEqual(p.settingScale(120)?.dimensions(.standard), Dimensions(1067, 600))
    }
    func testAutomaticSwitchCanWaitForDefaultAndExplicitToolbarOffSurvivesReload() throws {
        var p = Preferences()
        XCTAssertTrue(p.toolbarWhenConnected)
        p.autoResolutionPresetID = nil
        p.autoResolutionEnabled = true
        XCTAssertFalse(p.hasAutomaticDefault)
        p.toolbarWhenConnected = false
        let loaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertTrue(loaded.autoResolutionEnabled)
        XCTAssertNil(loaded.autoResolutionPresetID)
        XCTAssertFalse(loaded.toolbarWhenConnected)
    }
}
