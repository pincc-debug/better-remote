import XCTest
@testable import RemoteFitCore

final class ResolutionAdjustmentTests: XCTestCase {
    func testScalePresetsApplyFromBaseWithoutDrift() throws {
        let original = ResolutionAdjustment(.init(1400, 630))
        let larger = try XCTUnwrap(original.settingScale(120))
        XCTAssertEqual(larger.dimensions, .init(1167, 525))
        let more = try XCTUnwrap(larger.settingScale(80))
        XCTAssertEqual(more.dimensions, .init(1750, 788))
        XCTAssertEqual(try XCTUnwrap(more.settingScale(100)), original)
    }
    func testScalePresetBoundsAndStandardPresets() {
        XCTAssertNil(ResolutionAdjustment(.init(512, 512)).settingScale(120))
        XCTAssertNil(ResolutionAdjustment(.init(1280, 720)).settingScale(0))
        for preset in ScreenPreset.allCases {
            for percent in [80, 90, 100, 110, 120] {
                XCTAssertNotNil(ResolutionAdjustment(preset.dimensions(.standard)).settingScale(percent))
            }
        }
    }
    func testWidthAndHeightStepIndependently() throws {
        let original = ResolutionAdjustment(.init(1280, 720))
        let wider = try XCTUnwrap(original.stepping(.width, direction: 1))
        XCTAssertEqual(wider.dimensions, .init(1312, 720))
        XCTAssertEqual(try XCTUnwrap(wider.stepping(.width, direction: -1)), original)
        XCTAssertEqual(try XCTUnwrap(original.stepping(.height, direction: -1)).dimensions, .init(1280, 688))
        XCTAssertEqual(original.base, .init(1280, 720))
    }
    func testLargerTextReducesLogicalDesktopAndRoundTripDoesNotDrift() throws {
        let original = ResolutionAdjustment(.init(1366, 768))
        let larger = try XCTUnwrap(original.stepping(.scale, direction: 1))
        XCTAssertEqual(larger.scalePercent, 110)
        XCTAssertEqual(larger.dimensions, .init(1242, 698))
        XCTAssertEqual(try XCTUnwrap(larger.stepping(.scale, direction: -1)), original)
    }
    func testBoundsRejectUnsupportedRenderedAndBaseDimensions() {
        XCTAssertNil(ResolutionAdjustment(.init(512, 512)).stepping(.width, direction: -1))
        XCTAssertNil(ResolutionAdjustment(.init(512, 512)).stepping(.scale, direction: 1))
        XCTAssertNil(ResolutionAdjustment(.init(3840, 2160)).stepping(.width, direction: 1))
        XCTAssertNil(ResolutionAdjustment(.init(3840, 2160)).stepping(.scale, direction: -1))
        XCTAssertNil(ResolutionAdjustment(.init(1280, 720)).stepping(.height, direction: 0))
    }
    func testSaveCopyPreservesEffectiveSizeAndUsesNewIdentity() throws {
        let adjustment = try XCTUnwrap(ResolutionAdjustment(.init(1280, 720)).stepping(.scale, direction: 1))
        let first = adjustment.copyPreset(), second = adjustment.copyPreset()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.dimensions(.standard), adjustment.dimensions)
        let roundTrip = try JSONDecoder().decode(CustomPreset.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(roundTrip, first)
    }
}
