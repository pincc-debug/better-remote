import XCTest
@testable import RemoteFitCore

final class AutoFillPolicyTests: XCTestCase {
    private let area = CGRect(x: 0, y: 25, width: 1200, height: 800)
    private func window(_ change: (inout AutoFillPolicy.Window) -> Void = { _ in }) -> AutoFillPolicy.Window {
        var w = AutoFillPolicy.Window(role: "AXWindow", subrole: "AXStandardWindow", frame: CGRect(x: 100, y: 100, width: 800, height: 500), resizable: true)
        change(&w)
        return w
    }

    func testFillsOrdinaryStandardWindow() {
        XCTAssertEqual(AutoFillPolicy.decide(window(), area: area), .fill)
        XCTAssertTrue(AutoFillPolicy.shouldFill(window(), area: area))
    }

    func testSkipsNonStandardWindows() {
        for subrole in ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "AXSystemFloatingWindow", "AXUnknown", nil] as [String?] {
            XCTAssertEqual(AutoFillPolicy.decide(window { $0.subrole = subrole }, area: area), .skip(.notStandardWindow), "\(subrole ?? "nil")")
        }
        for role in ["AXSheet", "AXPopover", "AXDrawer", nil] as [String?] {
            XCTAssertEqual(AutoFillPolicy.decide(window { $0.role = role }, area: area), .skip(.notStandardWindow))
        }
    }

    func testSkipsSpecialStates() {
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.ownApplication = true }, area: area), .skip(.ownApplication))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.modal = true }, area: area), .skip(.modal))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.layer = 3 }, area: area), .skip(.floatingLayer))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.minimized = true }, area: area), .skip(.minimized))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.fullScreen = true }, area: area), .skip(.fullScreen))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.resizable = false }, area: area), .skip(.notResizable))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.frame = nil }, area: area), .skip(.noFrame))
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.frame = CGRect(x: 0, y: 0, width: 40, height: 40) }, area: area), .skip(.tooSmall))
    }

    func testAlreadyFilledIsNotFilledAgain() {
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.frame = self.area.insetBy(dx: 2, dy: 2) }, area: area), .skip(.alreadyFilled))
    }

    func testFillTargetRespectsToolbarWorkspace() {
        // Right toolbar expanded: the fill area ends at the toolbar; a window filling the whole screen
        // is not "filled" for that area and gets filled to the narrower workspace.
        let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let toolbar = CGRect(x: 1140, y: 300, width: 60, height: 300)
        let workspace = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: toolbar, in: screen, side: .right)
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.frame = screen }, area: workspace), .fill)
        XCTAssertEqual(AutoFillPolicy.decide(window { $0.frame = workspace }, area: workspace), .skip(.alreadyFilled))
    }

    // MARK: Tracker: no loops, respect manual resize until re-activated

    func testManualResizeIsRespectedUntilReactivated() {
        var tracker = AutoFillTracker()
        let a = AutoFillTracker.Key(pid: 1, window: 10), b = AutoFillTracker.Key(pid: 2, window: 20)
        let small = CGRect(x: 100, y: 100, width: 600, height: 400)
        XCTAssertTrue(tracker.allows(a, frame: small, area: area))
        tracker.didFill(a)
        XCTAssertFalse(tracker.allows(a, frame: area, area: area), "already at fill frame")
        XCTAssertFalse(tracker.allows(a, frame: small, area: area), "user resized while still in front")
        XCTAssertTrue(tracker.allows(b, frame: small, area: area))
        XCTAssertTrue(tracker.allows(a, frame: small, area: area), "re-activated later")
    }

    func testRetainDropsClosedWindows() {
        var tracker = AutoFillTracker()
        let a = AutoFillTracker.Key(pid: 1, window: 10)
        _ = tracker.allows(a, frame: .zero, area: area)
        tracker.didFill(a)
        tracker.retain([])
        XCTAssertNil(tracker.front)
        XCTAssertTrue(tracker.allows(a, frame: CGRect(x: 0, y: 0, width: 500, height: 400), area: area))
    }
}
