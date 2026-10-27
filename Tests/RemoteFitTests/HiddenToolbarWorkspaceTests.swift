import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

/// Fully hiding the expanded toolbar (setting, connect / disconnect switch, menu bar) must give its
/// space back to windows exactly like 收起 does.
@MainActor
final class HiddenToolbarWorkspaceTests: XCTestCase {
    private func switcher() -> FloatingSwitcher {
        _ = NSApplication.shared
        let switcher = FloatingSwitcher()
        switcher.reduceMotion = { true }
        switcher.configure(preferences: Preferences())
        return switcher
    }

    func testHidingExpandedToolbarReleasesItsSpaceWhileFrameIsStillKnown() {
        let switcher = switcher()
        defer { switcher.setEnabled(false) }
        switcher.showExpanded()
        XCTAssertEqual(switcher.presence, .expanded)
        var releases = 0
        var expandedDuringRelease = false
        switcher.onWillCollapse = { releases += 1; expandedDuringRelease = switcher.isExpanded }
        switcher.setEnabled(false)
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(expandedDuringRelease, "the region (reserved frame) must still resolve when windows reclaim space")
        XCTAssertEqual(switcher.presence, .hidden)
        XCTAssertFalse(switcher.isExpanded)
    }

    func testHidingTheBallOrAnAlreadyHiddenToolbarReleasesNothing() {
        let switcher = switcher()
        defer { switcher.setEnabled(false) }
        var releases = 0
        switcher.onWillCollapse = { releases += 1 }
        switcher.setEnabled(true)
        XCTAssertEqual(switcher.presence, .collapsed)
        switcher.setEnabled(false)
        switcher.setEnabled(false)
        XCTAssertEqual(releases, 0)
    }

    func testHiddenToolbarWorkspaceIsTheWholeVisibleFrame() throws {
        let switcher = switcher()
        defer { switcher.setEnabled(false) }
        switcher.showExpanded()
        let screen = try XCTUnwrap(switcher.actionScreen).visibleFrame
        let expanded = DesktopToolbarLayout.workspace(presence: switcher.presence, toolbar: switcher.reservedToolbarFrame, in: screen, side: .right)
        XCTAssertLessThan(expanded.width, screen.width)
        switcher.setEnabled(false)
        XCTAssertEqual(DesktopToolbarLayout.workspace(presence: switcher.presence, toolbar: switcher.reservedToolbarFrame, in: screen, side: .right), screen)
    }

    func testHideReleaseFillsWindowsNextToTheToolbar() async throws {
        let region = WorkspaceLayoutController.Region(area: CGRect(x: 0, y: 0, width: 1120, height: 800),
            screen: CGRect(x: 0, y: 0, width: 1200, height: 800), toolbar: CGRect(x: 1120, y: 0, width: 80, height: 800), side: .right)
        let near = ApplicationWindowCatalog.Window(pid: 123, id: 1, frame: CGRect(x: 100, y: 100, width: 1010, height: 400))
        var filled: [UInt32] = []
        var current: WorkspaceLayoutController.Region? = region
        let controller = WorkspaceLayoutController(visibleWindows: { [near] }, canAdjust: { true }, userInteracting: { false },
            foregroundPID: { 123 }, fill: { window, _ in filled.append(window.id) }, move: { _, _ in })
        defer { controller.cancel() }
        controller.region = { current }
        controller.setEnabled(true)
        let switcher = switcher()
        defer { switcher.setEnabled(false) }
        switcher.showExpanded()
        switcher.onWillCollapse = { controller.releaseToolbar() }
        switcher.onExpansionChanged = { if !switcher.isExpanded { current = nil; controller.setEnabled(false) } }
        switcher.setEnabled(false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(filled, [1])
    }
}
