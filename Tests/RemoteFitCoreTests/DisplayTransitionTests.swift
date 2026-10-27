import XCTest
@testable import RemoteFitCore

final class DisplayTransitionTests: XCTestCase {
    private let previous = Dimensions(1400, 630)
    private let next = Dimensions(630, 1400)
    private func display(_ id: UInt32, physical: Bool, main: Bool = false, mirror: UInt32 = 0) -> DisplayState {
        .init(id: id, uuid: "display-\(id)", hardwareKey: "hardware-\(id)", physical: physical,
              main: main, x: 0, y: 0, mirror: mirror,
              mode: .init(width: 1400, height: 630, pixelWidth: 2800, pixelHeight: 1260, refresh: 60))
    }
    private var old: DisplayState { display(42, physical: false, main: true) }
    private var candidate: DisplayState { display(43, physical: false) }
    private var physical: [DisplayState] { [display(1, physical: true, mirror: 42), display(2, physical: true, mirror: 42)] }

    /// Mac mini with its monitor asleep: changing display size swaps virtual -> virtual with no physical step.
    func testHeadlessScaleChangeHandsOffVirtualToVirtual() throws {
        let scaled = Dimensions(1167, 525)
        let targets = try DisplayTransition.targets(source: candidate, dimensions: scaled, physical: [], retiring: old)
        XCTAssertEqual(targets.map(\.id), [42, 43])
        XCTAssertTrue(targets[1].main); XCTAssertEqual(targets[1].mode.width, 1167)
        XCTAssertEqual(targets[0].mirror, 43); XCTAssertFalse(targets[0].main)
        var live = targets
        live[0].mode = old.mode
        XCTAssertTrue(DisplayTransition.matches(live, targets: targets, sourceID: 43))
        let settled = targets.filter { $0.id != 42 }
        XCTAssertTrue(DisplayTransition.matches(settled, targets: settled, sourceID: 43))
    }

    func testHeadlessFirstActivationNeedsNoPhysicalDisplay() throws {
        let targets = try DisplayTransition.targets(source: candidate, dimensions: next, physical: [])
        XCTAssertEqual(targets.map(\.id), [43]); XCTAssertTrue(targets[0].main)
    }

    func testHandoffKeepsOriginalSourceAndDoesNotRestorePhysicalModes() throws {
        let targets = try DisplayTransition.targets(source: candidate, dimensions: next, physical: physical, retiring: old)
        XCTAssertEqual(targets.map(\.id), [42, 43, 1, 2])
        XCTAssertTrue(targets[0].skipMode)
        XCTAssertFalse(targets[0].main)
        XCTAssertEqual(targets[0].mirror, 43)
        XCTAssertTrue(targets[0].skipOrigin)
        XCTAssertTrue(targets[1].main)
        XCTAssertEqual(targets[1].mode.pixelWidth, 1260)
        XCTAssertEqual(targets[1].mode.pixelHeight, 2800)
        for target in targets.suffix(2) {
            XCTAssertEqual(target.mirror, 43)
            XCTAssertTrue(target.skipMode)
            XCTAssertTrue(target.skipOrigin)
            XCTAssertEqual(target.mode, physical.first(where: { $0.id == target.id })?.mode)
        }
    }

    func testSamePlanCanHandMirrorsBackToRetainedSource() throws {
        let rollback = try DisplayTransition.targets(source: old, dimensions: previous, physical: physical, retiring: candidate)
        XCTAssertEqual(rollback.first(where: { $0.main })?.id, 42)
        XCTAssertEqual(rollback.filter(\.physical).map(\.mirror), [42, 42])
        XCTAssertEqual(rollback.first(where: { $0.id == 42 })?.uuid, old.uuid)
    }

    func testVerificationAllowsPhysicalMirrorModesToFollowSource() throws {
        let targets = try DisplayTransition.targets(source: candidate, dimensions: next, physical: physical, retiring: old)
        var live = targets
        for index in live.indices where live[index].physical { live[index].mode = targets[1].mode }
        XCTAssertTrue(DisplayTransition.matches(live, targets: targets, sourceID: 43))
        XCTAssertTrue(DisplayTransition.matches(live.filter { $0.id != 42 }, targets: targets.filter { $0.id != 42 }, sourceID: 43))
    }

    func testForeignDisplayHotplugAndWrongSourceCannotPassVerification() throws {
        let targets = try DisplayTransition.targets(source: candidate, dimensions: next, physical: physical, retiring: old)
        XCTAssertFalse(DisplayTransition.matches(Array(targets.dropLast()), targets: targets, sourceID: 43))
        XCTAssertFalse(DisplayTransition.matches(targets + [display(99, physical: true)], targets: targets, sourceID: 43))
        XCTAssertFalse(DisplayTransition.matches(targets + [targets[0]], targets: targets, sourceID: 43))
        for change: (inout DisplayState) -> Void in [
            { $0.uuid = "changed" }, { $0.main = false }, { $0.mirror = 42 },
            { $0.x = 100 }, { $0.mode.pixelHeight = 1400 }
        ] {
            var live = targets
            change(&live[1])
            XCTAssertFalse(DisplayTransition.matches(live, targets: targets, sourceID: 43))
        }
        var live = targets
        live[2].mirror = 42
        XCTAssertFalse(DisplayTransition.matches(live, targets: targets, sourceID: 43))
    }

    func testPhysicalSourcesForeignMirrorsAndDuplicateIDsAreRejected() {
        XCTAssertThrowsError(try DisplayTransition.targets(source: physical[0], dimensions: next, physical: physical, retiring: old))
        XCTAssertThrowsError(try DisplayTransition.targets(source: old, dimensions: next, physical: physical, retiring: old))
        XCTAssertThrowsError(try DisplayTransition.targets(source: candidate, dimensions: next, physical: physical + [physical[0]], retiring: old))
        XCTAssertThrowsError(try DisplayTransition.targets(source: candidate, dimensions: .init(4000, 900), physical: physical, retiring: old))
        var foreign = physical
        foreign[0].mirror = 99
        XCTAssertThrowsError(try DisplayTransition.targets(source: candidate, dimensions: next, physical: foreign, retiring: old))
    }

    /// Lid open: built-in (main) + external at its own 1x 4K mode. Both mirror the virtual source;
    /// verification only requires mirroring, not the external's mode or origin.
    func testLidOpenAllPhysicalDisplaysMirrorAndIgnoreModeAndOrigin() throws {
        var builtin = display(1, physical: true, main: true)
        builtin.mode = .init(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 120)
        var external = display(2, physical: true); external.x = 1728; external.y = -1440
        external.mode = .init(width: 3840, height: 2160, pixelWidth: 3840, pixelHeight: 2160, refresh: 60)
        let targets = try DisplayTransition.targets(source: candidate, dimensions: Dimensions(1252, 1156), physical: [builtin, external])
        for id: UInt32 in [1, 2] {
            let t = targets.first { $0.id == id }!
            XCTAssertEqual(t.mirror, 43); XCTAssertFalse(t.main); XCTAssertTrue(t.skipMode); XCTAssertTrue(t.skipOrigin)
        }
        var live = targets
        let i = live.firstIndex { $0.id == 2 }!
        live[i].x = 0; live[i].y = 0
        live[i].mode = .init(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refresh: 60)
        XCTAssertTrue(DisplayTransition.matches(live, targets: targets, sourceID: 43))
        live[i].mirror = 0
        XCTAssertFalse(DisplayTransition.matches(live, targets: targets, sourceID: 43))
    }
}
