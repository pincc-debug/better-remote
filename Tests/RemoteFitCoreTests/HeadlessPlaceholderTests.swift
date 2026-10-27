import XCTest
@testable import RemoteFitCore

final class HeadlessPlaceholderTests: XCTestCase {
    private let mode = DisplayMode(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refresh: 60)
    private func state(_ id: UInt32, key: String, physical: Bool = true, main: Bool = false, mirror: UInt32 = 0) -> DisplayState {
        DisplayState(id: id, uuid: "u\(id)", hardwareKey: key, physical: physical, main: main, x: 0, y: 0, mirror: mirror, mode: mode)
    }
    private let placeholderKey = "1970170734:1986622068:0:false"

    func testDetectsMacOSHeadlessPlaceholder() {
        XCTAssertTrue(HeadlessPlaceholder.isPlaceholder(hardwareKey: placeholderKey))
        XCTAssertFalse(HeadlessPlaceholder.isPlaceholder(hardwareKey: "1552:41012:0:true"))
        XCTAssertFalse(HeadlessPlaceholder.isPlaceholder(hardwareKey: "1970170734:1986622068:5:false"))
        XCTAssertFalse(HeadlessPlaceholder.isPlaceholder(hardwareKey: "\(ActivationBase.ownVendor):1:0:false"))
    }

    func testPlaceholderIsNeverMirrored() throws {
        let saved = [state(319, key: placeholderKey, main: true)]
        let source = state(320, key: "\(ActivationBase.ownVendor):1:0:false", physical: false)
        let targets = try DisplayTransition.targets(source: source, dimensions: Dimensions(1252, 1156),
                                                    physical: HeadlessPlaceholder.mirrorable(saved))
        XCTAssertEqual(targets.map(\.id), [320])
        XCTAssertFalse(targets.contains { $0.mirror != 0 })
    }

    func testRealMonitorStillMirroredBesidePlaceholder() throws {
        let saved = [state(319, key: placeholderKey), state(3, key: "1552:1:2:false", main: true)]
        let source = state(320, key: "\(ActivationBase.ownVendor):1:0:false", physical: false)
        let targets = try DisplayTransition.targets(source: source, dimensions: Dimensions(1252, 1156),
                                                    physical: HeadlessPlaceholder.mirrorable(saved))
        XCTAssertEqual(Set(targets.map(\.id)), [3, 320])
        XCTAssertEqual(targets.first { $0.id == 3 }?.mirror, 320)
    }

    func testVerificationIgnoresPlaceholderThatStaysOnline() {
        let live = [state(321, key: placeholderKey), state(320, key: "\(ActivationBase.ownVendor):1:0:false", physical: false, main: true)]
        XCTAssertEqual(HeadlessPlaceholder.ignoringPlaceholders(live).map(\.id), [320])
    }
}

final class HeadlessPlaceholderRestoreTests: XCTestCase {
    private let mode = DisplayMode(width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refresh: 60)
    private func state(_ id: UInt32, key: String, physical: Bool = true, main: Bool = false) -> DisplayState {
        DisplayState(id: id, uuid: "u\(id)", hardwareKey: key, physical: physical, main: main, x: 0, y: 0, mirror: 0, mode: mode)
    }
    private let placeholder = "1970170734:1986622068:0:false"
    private let own = "\(ActivationBase.ownVendor):1:0:false"

    /// Lid closed, monitor off: only our virtual display and macOS's placeholder are online.
    func testPlaceholderDoesNotCountAsReturnedMonitor() throws {
        let saved = [state(3, key: "1552:1:2:false", main: true)]
        let live = [state(319, key: placeholder), state(318, key: own, physical: false, main: true)]
        XCTAssertEqual(try RestorePlan.outcome(saved: saved, live: live), .deferred)
    }

    func testRealMonitorBackStillRestores() throws {
        let saved = [state(3, key: "1552:1:2:false", main: true)]
        let live = [state(319, key: placeholder), state(3, key: "1552:1:2:false")]
        XCTAssertEqual(try RestorePlan.outcome(saved: saved, live: live), .restore([saved[0]]))
    }

    func testSnapshotOfOnlyPlaceholderReleasesWhenMonitorBack() throws {
        let saved = [state(319, key: placeholder, main: true)]
        let live = [state(3, key: "1552:1:2:false", main: true)]
        XCTAssertEqual(try RestorePlan.outcome(saved: saved, live: live), .release)
    }
}
