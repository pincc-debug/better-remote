import XCTest
@testable import RemoteFit
import RemoteFitCore

@MainActor
final class WorkspaceLayoutControllerTests: XCTestCase {
    private var region: WorkspaceLayoutController.Region {
        .init(area: CGRect(x: 0, y: 0, width: 1120, height: 800),
              screen: CGRect(x: 0, y: 0, width: 1200, height: 800),
              toolbar: CGRect(x: 1120, y: 0, width: 80, height: 800), side: .right)
    }
    private var overlapping: ApplicationWindowCatalog.Window {
        .init(pid: 123, id: 1, frame: CGRect(x: 900, y: 100, width: 280, height: 400))
    }

    func testExpansionAndLaterWindowChangesMoveOnlyActualOverlaps() async throws {
        let far = ApplicationWindowCatalog.Window(pid: 456, id: 2, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        var list = [overlapping, far]
        var moved: [UInt32] = []
        let controller = WorkspaceLayoutController(visibleWindows: { list },
            canAdjust: { true }, userInteracting: { false }, foregroundPID: { 456 }, move: { window, region in
                moved.append(window.id)
                let target = WindowLayout.avoidingToolbar(window.frame, toolbar: region.toolbar, screen: region.screen, side: region.side)!
                XCTAssertEqual(target.size, window.frame.size)
                list = list.map { $0.id == window.id ? .init(pid: window.pid, id: window.id, frame: target) : $0 }
            })
        defer { controller.cancel() }
        let region = region
        controller.region = { region }
        controller.setEnabled(true)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(moved, [1])
        XCTAssertEqual(list.first { $0.id == 2 }?.frame, far.frame)
        list.append(.init(pid: 789, id: 3, frame: overlapping.frame))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(moved, [1, 3])
        XCTAssertEqual(list.first { $0.id == 2 }?.frame, far.frame)
    }

    func testDragReleaseTriggersAvoidanceButNeverMovesWhileDragging() async throws {
        var interacting = true
        var window = overlapping
        var moves = 0
        let controller = WorkspaceLayoutController(visibleWindows: { [window] },
            canAdjust: { true }, userInteracting: { interacting }, foregroundPID: { 123 }, move: { candidate, region in
                moves += 1
                let target = WindowLayout.avoidingToolbar(candidate.frame, toolbar: region.toolbar, screen: region.screen, side: region.side)!
                window = .init(pid: candidate.pid, id: candidate.id, frame: target)
            })
        defer { controller.cancel() }
        let region = region
        controller.region = { region }
        controller.setEnabled(true)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(moves, 0)
        interacting = false
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(moves, 1)
        interacting = true
        window = overlapping
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(moves, 1)
        interacting = false
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(moves, 2)
    }

    func testAppSwitchRechecksOverlapsButStableFailedMovesDoNotLoop() async throws {
        var front: Int32 = 123
        let window = overlapping
        var moves = 0
        let controller = WorkspaceLayoutController(visibleWindows: { [window] },
            canAdjust: { true }, userInteracting: { false }, foregroundPID: { front }, move: { _, _ in moves += 1 })
        defer { controller.cancel() }
        let region = region
        controller.region = { region }
        controller.setEnabled(true)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(moves, 1)
        front = 456
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(moves, 2)
    }

    func testDisablingStopsAvoidanceWithoutFillingWindows() async throws {
        let window = overlapping
        var moves = 0
        let controller = WorkspaceLayoutController(visibleWindows: { [window] },
            canAdjust: { true }, userInteracting: { false }, foregroundPID: { 123 }, move: { _, _ in moves += 1 })
        let region = region
        controller.region = { region }
        controller.setEnabled(true)
        controller.setEnabled(false)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(moves, 0)
    }

    func testExplicitCollapseFillsOnlyWindowsWithinTenPointsAndSurvivesRender() async throws {
        let region = region
        let near = ApplicationWindowCatalog.Window(pid: 123, id: 1, frame: CGRect(x: 100, y: 100, width: 1010, height: 400))
        let far = ApplicationWindowCatalog.Window(pid: 123, id: 2, frame: CGRect(x: 100, y: 100, width: 1009, height: 400))
        var filled: [UInt32] = []
        let controller = WorkspaceLayoutController(visibleWindows: { [near, far] }, canAdjust: { true }, userInteracting: { false },
            foregroundPID: { 123 }, fill: { window, _ in filled.append(window.id) }, move: { _, _ in XCTFail("No overlap") })
        defer { controller.cancel() }
        controller.region = { region }
        controller.setEnabled(true)
        controller.releaseToolbar()
        // onExpansionChanged renders after onWillCollapse; this must not cancel fill.
        controller.setEnabled(false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(filled, [1])
    }

    func testReexpansionCancelsPendingCollapseFill() async throws {
        let region = region
        let near = ApplicationWindowCatalog.Window(pid: 123, id: 1, frame: CGRect(x: 100, y: 100, width: 1010, height: 400))
        var fills = 0
        let controller = WorkspaceLayoutController(visibleWindows: { [near] }, canAdjust: { true }, userInteracting: { false },
            foregroundPID: { 123 }, fill: { _, _ in fills += 1 }, move: { _, _ in })
        defer { controller.cancel() }
        controller.region = { region }
        controller.setEnabled(true)
        controller.releaseToolbar()
        controller.setEnabled(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fills, 0)
    }
}
