import XCTest
@testable import RemoteFitCore

final class DisplayReconfigurationTests: XCTestCase {
    private let mode = DisplayMode(width: 1366, height: 768, pixelWidth: 2732, pixelHeight: 1536, refresh: 60)
    private var baseline: [DisplayState] {
        [.init(id: 42, uuid: "virtual", hardwareKey: "virtual", physical: false, main: true, x: 0, y: 0, mirror: 0, mode: mode),
         .init(id: 1, uuid: "physical", hardwareKey: "physical", physical: true, main: false, x: 0, y: 0, mirror: 42, mode: mode)]
    }

    func testPortraitChangesOnlySourceMode() throws {
        let target = try DisplayReconfiguration.target(in: baseline, sourceID: 42, dimensions: .init(630, 1400))
        XCTAssertEqual(target.id, 42)
        XCTAssertEqual(target.uuid, "virtual")
        XCTAssertTrue(target.main)
        XCTAssertEqual(target.mirror, 0)
        XCTAssertTrue(target.skipOrigin)
        XCTAssertFalse(target.skipMode)
        XCTAssertEqual(target.mode.width, 630)
        XCTAssertEqual(target.mode.height, 1400)
        XCTAssertEqual(target.mode.pixelWidth, 1260)
        XCTAssertEqual(target.mode.pixelHeight, 2800)
    }

    func testMirrorModeCanFollowSourceWithoutBeingConsideredNewTopology() throws {
        let target = try DisplayReconfiguration.target(in: baseline, sourceID: 42, dimensions: .init(1502, 845))
        var live = baseline
        live[0] = target
        live[1].mode = target.mode
        XCTAssertTrue(DisplayReconfiguration.matches(live, baseline: baseline, target: target))
        live[0].mode.pixelWidth = 1502
        XCTAssertFalse(DisplayReconfiguration.matches(live, baseline: baseline, target: target))
    }

    func testChangedIdentityMainOriginOrMirrorIsRejected() {
        for mutation: (inout DisplayState) -> Void in [
            { $0.id = 43 }, { $0.uuid = "replacement" }, { $0.main = false },
            { $0.x = -630 }, { $0.y = 100 }, { $0.mirror = 1 }, { $0.physical = true }
        ] {
            var live = baseline
            mutation(&live[0])
            XCTAssertFalse(DisplayReconfiguration.sameTopology(live, as: baseline))
        }
        var live = baseline
        live[1].mirror = 0
        XCTAssertFalse(DisplayReconfiguration.sameTopology(live, as: baseline))
        XCTAssertThrowsError(try DisplayReconfiguration.target(in: live, sourceID: 42, dimensions: .init(1500, 900)))
    }

    func testPhysicalAndMissingSourcesAreNeverReconfigured() {
        XCTAssertThrowsError(try DisplayReconfiguration.target(in: baseline, sourceID: 1, dimensions: .init(1500, 900)))
        XCTAssertThrowsError(try DisplayReconfiguration.target(in: baseline, sourceID: 99, dimensions: .init(1500, 900)))
        XCTAssertThrowsError(try DisplayReconfiguration.target(in: baseline, sourceID: 42, dimensions: .init(4000, 900)))
    }

    func testHotplugAndDuplicateIDsCannotPassVerification() {
        XCTAssertFalse(DisplayReconfiguration.sameTopology(Array(baseline.dropLast()), as: baseline))
        XCTAssertFalse(DisplayReconfiguration.sameTopology(baseline + [baseline[1]], as: baseline))
        XCTAssertFalse(DisplayReconfiguration.sameTopology([baseline[0], baseline[0]], as: baseline))
        XCTAssertTrue(DisplayReconfiguration.sameTopology(baseline.reversed(), as: baseline))
    }
}
