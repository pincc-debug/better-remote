import XCTest
@testable import RemoteFitCore

final class ZeroDisplayActivationTests: XCTestCase {
    private func display(_ id: UInt32, vendor: UInt32 = 1552) -> DisplayState {
        .init(id: id, uuid: "U\(id)", hardwareKey: "\(vendor):1:\(id):false", physical: vendor != ActivationBase.ownVendor,
              main: id == 1, x: 0, y: 0, mirror: 0,
              mode: .init(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refresh: 60))
    }

    /// Lid closed + external monitor powered off: CGGetOnlineDisplayList returns nothing.
    func testNoOnlineDisplayIsTolerant() {
        let p = ZeroDisplayActivation.policy(live: [])
        XCTAssertEqual(p, .noDisplayOnline)
        XCTAssertGreaterThan(p.createAttempts, 1)
        XCTAssertGreaterThan(Double(p.readyPolls) * p.readyPollInterval, 3.0)
        XCTAssertTrue(p.acceptInitialModeMismatch)
        XCTAssertTrue(p.wakeDisplays)
        // Zero displays is a valid activation base, not a conflict.
        XCTAssertEqual(ActivationBase.verdict([]), .ok)
    }

    /// Any online display (built-in, external, foreign virtual screen) keeps the strict path.
    func testOnlineDisplaysKeepStrictBehaviour() {
        XCTAssertEqual(ZeroDisplayActivation.policy(live: [display(1)]), .standard)
        XCTAssertEqual(ZeroDisplayActivation.policy(live: [display(1), display(2, vendor: 25001)]), .standard)
        XCTAssertEqual(ZeroDisplayActivation.standard.createAttempts, 1)
        XCTAssertFalse(ZeroDisplayActivation.standard.acceptInitialModeMismatch)
    }

    /// The transition for a zero-display Mac is just the virtual source as main.
    func testTransitionWithNoPhysicalDisplays() throws {
        var source = display(300, vendor: ActivationBase.ownVendor)
        source.main = false
        let targets = try DisplayTransition.targets(source: source, dimensions: .init(1252, 1156), physical: [])
        XCTAssertEqual(targets.map(\.id), [300])
        XCTAssertTrue(targets[0].main)
        XCTAssertEqual(targets[0].mode.pixelWidth, 2504)
    }
}
