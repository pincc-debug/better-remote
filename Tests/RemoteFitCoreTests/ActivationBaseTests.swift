import XCTest
@testable import RemoteFitCore

final class ActivationBaseTests: XCTestCase {
    let mode = DisplayMode(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refresh: 60)
    func d(_ id: UInt32, key: String, main: Bool = false, mirror: UInt32 = 0) -> DisplayState {
        .init(id: id, uuid: "u\(id)", hardwareKey: key, physical: !ActivationBase.isOwn(hardwareKey: key),
              main: main, x: 0, y: 0, mirror: mirror, mode: mode)
    }
    /// Headless Mac mini: monitor asleep, only a system/remote-tool virtual screen ('virt' model).
    func testHeadlessForeignVirtualScreenIsABaseDisplay() throws {
        let foreign = d(5, key: "1970170734:1987211892:0:false", main: true)
        XCTAssertTrue(foreign.physical)
        XCTAssertEqual(ActivationBase.verdict([foreign]), .ok)
        let source = DisplayState(id: 43, uuid: "v", hardwareKey: "21062:1:9:false", physical: false, main: false, x: 0, y: 0, mirror: 0, mode: mode)
        let targets = try DisplayTransition.targets(source: source, dimensions: Dimensions(1252, 1156), physical: [foreign])
        XCTAssertEqual(targets.first { $0.id == 5 }!.mirror, 43)
    }
    func testOwnLeftoverIsDetected() {
        XCTAssertEqual(ActivationBase.verdict([d(1, key: "1552:41055:1:true", main: true), d(9, key: "21062:1:77:false")]), .ownLeftover([9]))
    }
    func testMirrorInsideSetIsAllowedButDanglingIsNot() throws {
        let a = d(1, key: "a", main: true), b = d(2, key: "b", mirror: 1)
        XCTAssertEqual(ActivationBase.verdict([a, b]), .ok)
        XCTAssertEqual(ActivationBase.verdict([a, d(3, key: "c", mirror: 99)]), .brokenMirror([3]))
        let source = DisplayState(id: 43, uuid: "v", hardwareKey: "21062:1:9:false", physical: false, main: false, x: 0, y: 0, mirror: 0, mode: mode)
        XCTAssertEqual(try DisplayTransition.targets(source: source, dimensions: Dimensions(1252, 1156), physical: [a, b]).filter(\.physical).map(\.mirror), [43, 43])
        // Restore puts the original mirror pairing back.
        guard case .restore(let back) = try RestorePlan.outcome(saved: [a, b], live: [a, b]) else { return XCTFail() }
        XCTAssertEqual(back.first { $0.id == 2 }!.mirror, 1)
    }
}
