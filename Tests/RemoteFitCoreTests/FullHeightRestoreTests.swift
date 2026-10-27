import XCTest
@testable import RemoteFitCore

final class FullHeightRestoreTests: XCTestCase {
    private let panel = Dimensions(3456, 2234)
    private func mode(_ width: Int = 1728, _ height: Int, scale: Int = 2, refresh: Double = 120, id: Int = 0) -> DisplayMode {
        .init(width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refresh: refresh, modeID: id)
    }

    func testCroppedBuiltInReturnsToFullHeightWithoutChangingScaleOrRefresh() {
        let full = mode(1728, 1117, id: 54)
        XCTAssertEqual(FullHeightRestore.mode(saved: mode(1728, 1080), available: [mode(1728, 1117, refresh: 60), full], nativePixels: panel, builtin: true), full)
    }

    func testFractionalRefreshIsPreservedInsteadOfChoosingNearbyIntegerRate() {
        let full = mode(1728, 1117, refresh: 59.94, id: 56)
        XCTAssertEqual(FullHeightRestore.mode(saved: mode(1728, 1080, refresh: 59.94), available: [mode(1728, 1117, refresh: 60), full], nativePixels: panel, builtin: true), full)
    }

    func testOtherScalingLevelsUseNativeAspectAndRetainBackingScale() {
        let full = mode(1496, 967)
        XCTAssertEqual(FullHeightRestore.mode(saved: mode(1496, 935), available: [mode(1496, 967, scale: 1), full], nativePixels: panel, builtin: true), full)
        let unscaled = mode(3456, 2234, scale: 1)
        XCTAssertEqual(FullHeightRestore.mode(saved: mode(3456, 2160, scale: 1), available: [unscaled], nativePixels: panel, builtin: true), unscaled)
    }

    func testFullHeightExternalAndNonNotchedPanelsRemainUnchanged() {
        let cropped = mode(1728, 1080)
        let full = mode(1728, 1117)
        XCTAssertEqual(FullHeightRestore.mode(saved: full, available: [cropped, full], nativePixels: panel, builtin: true), full)
        XCTAssertEqual(FullHeightRestore.mode(saved: cropped, available: [full], nativePixels: panel, builtin: false), cropped)
        XCTAssertEqual(FullHeightRestore.mode(saved: cropped, available: [full], nativePixels: .init(3456, 2160), builtin: true), cropped)
    }

    func testUnavailableModesNeverChangeResolutionScaleOrRefreshAsFallback() {
        let cropped = mode(1728, 1080)
        for available in [[], [mode(1728, 1117, refresh: 60)], [mode(1728, 1117, scale: 1)], [mode(1728, 1120)], [mode(2056, 1329)]] {
            XCTAssertEqual(FullHeightRestore.mode(saved: cropped, available: available, nativePixels: panel, builtin: true), cropped)
        }
        XCTAssertEqual(FullHeightRestore.mode(saved: cropped, available: [mode(1728, 1117)], nativePixels: nil, builtin: true), cropped)
    }
}
