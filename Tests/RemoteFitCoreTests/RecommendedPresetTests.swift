import XCTest
@testable import RemoteFitCore

final class RecommendedPresetTests: XCTestCase {
    func testDefaultListStartsWithRecommendedPhoneSizesThenKeepsOldPhoneAlternatives() {
        let specs = CustomPreset.factorySpecs()
        XCTAssertEqual(specs.map(\.id), ["factory:phoneRecommended", "factory:portraitRecommended",
                                         "factory:phone", "factory:portrait",
                                         "factory:widescreen", "factory:tablet", "factory:wideTablet"])
        XCTAssertEqual(specs[0].title, "手机横屏（保留操作栏）")
        XCTAssertEqual(specs[0].dimensions(.standard), Dimensions(1294, 720))
        XCTAssertEqual(specs[1].title, "手机竖屏（保留操作栏）")
        XCTAssertEqual(specs[1].dimensions(.standard), Dimensions(604, 1138))
        XCTAssertGreaterThan(specs[0].width, specs[0].height, "landscape glyph")
        XCTAssertLessThan(specs[1].width, specs[1].height, "portrait glyph")
        XCTAssertFalse(specs[0].title.contains(":") || specs[1].title.contains(":"), "no ratio in the name")
        XCTAssertEqual(specs.map(\.title), ["手机横屏（保留操作栏）", "手机竖屏（保留操作栏）", "手机横屏（全屏）", "手机竖屏（全屏）",
                                            "标准宽屏", "平板横屏", "宽屏平板"])
        XCTAssertEqual(specs.map { $0.dimensions(.standard) }, [Dimensions(1294, 720), Dimensions(604, 1138), Dimensions(1400, 630),
                                                               Dimensions(630, 1400), Dimensions(1280, 720), Dimensions(1024, 768), Dimensions(1280, 800)])
        for spec in specs { XCTAssertNil(spec.title.range(of: #"\d+\s*:\s*\d+"#, options: .regularExpression), "no ratio in \(spec.title)") }
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count)
        for spec in specs { XCTAssertNoThrow(try spec.validate()) }
        for spec in CustomPreset.recommendedSpecs {
            // The virtual display is created at exactly these logical sizes (512…3840 per side, HiDPI ×2 pixels).
            XCTAssertTrue(CustomPreset.isSupported(spec.dimensions(.standard)))
            XCTAssertEqual(ResolutionAdjustment(spec.dimensions(.standard)).dimensions, spec.dimensions(.standard))
        }
    }

    func testNewInstallTargetsRecommendedLandscapeOnConnect() throws {
        var p = Preferences()
        XCTAssertEqual(p.autoResolutionPresetID, CustomPreset.recommendedLandscapeID)
        XCTAssertTrue(p.hasAutomaticDefault)
        XCTAssertTrue(p.autoResolutionEnabled)
        XCTAssertEqual(p.configuration(for: nil).selectedResolutionID, CustomPreset.recommendedLandscapeID)
        XCTAssertEqual(CustomPreset.factorySpecs().first { $0.id == CustomPreset.recommendedLandscapeID }?.title,
                       "手机横屏（保留操作栏）")
        p.setAutomaticResolutionEnabled(false)
        XCTAssertEqual(p.autoResolutionPresetID, CustomPreset.recommendedLandscapeID)
        p.setAutomaticResolutionEnabled(true)
        XCTAssertEqual(p.autoResolutionPresetID, CustomPreset.recommendedLandscapeID)
        let reloaded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(reloaded.autoResolutionPresetID, CustomPreset.recommendedLandscapeID)
        XCTAssertTrue(reloaded.autoResolutionEnabled)
        // Existing prefs files that never stored the key keep resolution off.
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"seededFactorySpecs":true}"#.utf8))
        XCTAssertFalse(legacy.autoResolutionEnabled)
    }

    func testSavedListAndSelectionAreLeftAlone() throws {
        // A user who already has the old factory list (seeded) and their own choice keeps both exactly.
        let saved = #"""
        {"seededFactorySpecs":true,"selectedCustomID":"factory:portrait","autoResolutionEnabled":true,"autoResolutionPresetID":"factory:phone",
         "customPresets":[{"id":"factory:phone","name":"手机横屏 · 20:9","width":1400,"height":630},
                          {"id":"factory:portrait","name":"手机竖屏 · 9:20","width":630,"height":1400},
                          {"id":"mine","name":"我的","width":1252,"height":1156}]}
        """#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(saved.utf8))
        XCTAssertEqual(p.customPresets.map(\.id), ["factory:phone", "factory:portrait", "mine"])
        XCTAssertEqual(p.customPresets.map(\.name), ["手机横屏 · 20:9", "手机竖屏 · 9:20", "我的"])
        XCTAssertEqual(p.selectedCustomID, "factory:portrait")
        XCTAssertEqual(p.autoResolutionPresetID, "factory:phone")
        XCTAssertTrue(p.autoResolutionEnabled && p.hasAutomaticDefault)
        XCTAssertEqual(p.selectedCustom?.dimensions(.standard), Dimensions(630, 1400))
    }

    func testSavedFileWithoutTargetDoesNotGainOne() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"seededFactorySpecs":true,"customPresets":[]}"#.utf8))
        XCTAssertNil(p.autoResolutionPresetID)
        XCTAssertTrue(p.customPresets.isEmpty)
    }
}
