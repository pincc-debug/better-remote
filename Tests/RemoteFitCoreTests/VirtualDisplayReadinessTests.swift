import XCTest
@testable import RemoteFitCore

final class VirtualDisplayReadinessTests: XCTestCase {
    private let dimensions = Dimensions(630, 1400)
    private func source(hidpi: Bool) -> DisplayState {
        .init(id: 300, uuid: "virtual", hardwareKey: "virtual", physical: false,
              main: true, x: 0, y: 0, mirror: 0,
              mode: .init(width: 630, height: 1400, pixelWidth: hidpi ? 1260 : 630,
                          pixelHeight: hidpi ? 2800 : 1400, refresh: 60))
    }
    private var policy: ZeroDisplayActivation {
        var value = ZeroDisplayActivation.standard
        value.readyPolls = 3
        return value
    }

    private func mode(hidpi: Bool) -> DisplayMode { source(hidpi: hidpi).mode }
    private func probe(_ hidpi: Bool) -> VirtualDisplayProbe {
        .init(source: source(hidpi: false), modes: [mode(hidpi: hidpi)])
    }

    func testDelayedHiDPIModeWaitsInsteadOfFallingBackImmediately() throws {
        var samples = [VirtualDisplayProbe(source: nil, modes: []), probe(false), probe(true)]
        var pauses = 0
        let result = try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { samples.removeFirst() }, pause: { _ in pauses += 1 })
        XCTAssertEqual(result.mode, mode(hidpi: true))
        XCTAssertEqual(pauses, 2)
    }

    func testAdvertisedHiDPICanBeSelectedWhileCurrentModeIsStandard() throws {
        let ready = try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { self.probe(true) }, pause: { _ in XCTFail("Target already available") })
        XCTAssertEqual(ready.source.mode.pixelWidth, 630)
        XCTAssertEqual(ready.mode.pixelWidth, 1260)
        let targets = try DisplayTransition.targets(source: ready.source, dimensions: dimensions,
                                                     physical: [], selectedMode: ready.mode)
        XCTAssertFalse(DisplayTransition.matches([ready.source], targets: targets, sourceID: 300))
        XCTAssertTrue(DisplayTransition.matches([source(hidpi: true)], targets: targets, sourceID: 300))
    }

    func testStandardFallbackPreservesDesktopSizeAndRequiresExactVerification() throws {
        var reads = 0
        let ready = try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { reads += 1; return self.probe(false) }, pause: { _ in })
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(ready.mode, mode(hidpi: false))
        let targets = try DisplayTransition.targets(source: ready.source, dimensions: dimensions,
                                                     physical: [], selectedMode: ready.mode)
        XCTAssertTrue(DisplayTransition.matches([source(hidpi: false)], targets: targets, sourceID: 300))
        var wrong = source(hidpi: false)
        wrong.mode.height = 1399
        XCTAssertFalse(DisplayTransition.matches([wrong], targets: targets, sourceID: 300))
    }

    func testHiDPIPreferredRegardlessOfModeListOrder() {
        for modes in [[mode(hidpi: false), mode(hidpi: true)], [mode(hidpi: true), mode(hidpi: false)]] {
            XCTAssertEqual(VirtualDisplayReadiness.select(modes, dimensions: dimensions, scale: 2), mode(hidpi: true))
        }
    }

    func testUnsupportedSizeFailsWithoutChoosingNearbyMode() {
        var wrong = mode(hidpi: true)
        wrong.width = 640
        XCTAssertThrowsError(try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { .init(source: self.source(hidpi: false), modes: [wrong]) }, pause: { _ in })) { error in
            XCTAssertTrue(error.localizedDescription.contains("系统未提供"))
        }
    }

    func testDisappearedDisplayDoesNotReturnStaleModes() {
        var samples = [probe(false), .init(source: nil, modes: []), .init(source: nil, modes: [])]
        XCTAssertThrowsError(try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { samples.removeFirst() }, pause: { _ in })) { error in
            XCTAssertEqual(error.localizedDescription, "虚拟屏幕未就绪。")
        }
    }

    func testSnapshotFailureIsNotHidden() {
        XCTAssertThrowsError(try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { throw FitError.message("snapshot failed") }, pause: { _ in XCTFail("Must propagate") }))
    }

    func testWrongDensityOrRefreshIsNotAccepted() {
        var wrong = mode(hidpi: true)
        wrong.pixelHeight = 1400
        XCTAssertNil(VirtualDisplayReadiness.select([wrong], dimensions: dimensions, scale: 2))
        wrong = mode(hidpi: false); wrong.refresh = 30
        XCTAssertNil(VirtualDisplayReadiness.select([wrong], dimensions: dimensions, scale: 1))
        wrong.refresh = 59.94
        XCTAssertNotNil(VirtualDisplayReadiness.select([wrong], dimensions: dimensions, scale: 1))
    }

    func testMirroredSourceWaitsUnlessExtendedActivationAllowsIt() throws {
        var mirrored = source(hidpi: true)
        mirrored.mirror = 4
        let probe = VirtualDisplayProbe(source: mirrored, modes: [mode(hidpi: true)])
        XCTAssertThrowsError(try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { probe }, pause: { _ in })) { error in
            XCTAssertEqual(error.localizedDescription, "虚拟屏幕未就绪。")
        }
        let ready = try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { probe }, pause: { _ in XCTFail("Mode is already advertised") }, allowsMirroredSource: true)
        XCTAssertEqual(ready.mode.pixelWidth, 1260)
        XCTAssertEqual(ready.source.mirror, 4)
    }

    func testPhysicalDisplayCannotBeSelected() {
        var wrong = source(hidpi: true); wrong.physical = true
        XCTAssertThrowsError(try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy,
            sample: { .init(source: wrong, modes: [wrong.mode]) }, pause: { _ in }))
    }

    func testRollbackKeepsOriginalStandardDensity() throws {
        let old = source(hidpi: false)
        var incoming = source(hidpi: true); incoming.id = 301; incoming.uuid = "incoming"
        let rollback = try DisplayTransition.targets(source: old, dimensions: dimensions,
            physical: [], retiring: incoming, selectedMode: old.mode)
        XCTAssertEqual(rollback.first(where: { $0.id == old.id })?.mode, old.mode)
        XCTAssertTrue(DisplayTransition.matches(rollback, targets: rollback, sourceID: old.id))
        var wrong = rollback
        wrong[1].mode = incoming.mode
        XCTAssertFalse(DisplayTransition.matches(wrong, targets: rollback, sourceID: old.id))
    }

    func testTransitionRejectsUnrelatedSelectedMode() {
        XCTAssertThrowsError(try DisplayTransition.targets(source: source(hidpi: true), dimensions: .init(800, 600),
            physical: [], selectedMode: mode(hidpi: true)))
    }
}
