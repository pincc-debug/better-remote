import XCTest
@testable import RemoteFitCore

final class RemoteUIInteractionTests: XCTestCase {
    func testQuickTapLaunchesButHoldDoesNotLaunchOnRelease() {
        var tap = ApplicationPress()
        XCTAssertFalse(tap.update(elapsed: 0.12, distance: 0, inside: true))
        XCTAssertTrue(tap.shouldLaunch(inside: true))
        var hold = ApplicationPress()
        XCTAssertTrue(hold.update(elapsed: 0.5, distance: 2, inside: true))
        XCTAssertFalse(hold.update(elapsed: 1, distance: 2, inside: true))
        XCTAssertFalse(hold.shouldLaunch(inside: true))
    }

    func testDraggingOrLeavingCancelsEvenWhenPointerReturns() {
        for distance in [0.0, 20.0] {
            var press = ApplicationPress()
            XCTAssertFalse(press.update(elapsed: 0.1, distance: distance, inside: distance > 0))
            XCTAssertFalse(press.update(elapsed: 0.8, distance: 0, inside: true))
            XCTAssertFalse(press.shouldLaunch(inside: true))
        }
    }

    func testDockEdgesKeepFirstPresetReachableIncludingPartialRows() {
        XCTAssertEqual(ReachablePresetGrid.slots(count: 4, columns: 3, side: .left), [0, 1, 2, 3, nil, nil])
        XCTAssertEqual(ReachablePresetGrid.slots(count: 4, columns: 3, side: .right), [2, 1, 0, nil, nil, 3])
        XCTAssertEqual(ReachablePresetGrid.slots(count: 4, columns: 3, side: .top), [0, 1, 2, 3, nil, nil])
        XCTAssertEqual(ReachablePresetGrid.slots(count: 4, columns: 3, side: .bottom), [3, nil, nil, 0, 1, 2])
    }

    func testResolutionPanelShrinksToContentAndKeepsDockEdge() {
        let screen = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        for side in ToolbarSide.allCases {
            let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 10, side: side)
            let base = DesktopToolbarLayout.expandedPanel(to: toolbar, in: screen, side: side)
            for (count, expected) in [(0, 312.0), (1, 312.0), (2, 360.0), (6, 528.0), (30, 528.0)] {
                let panel = DesktopToolbarLayout.resolutionPanel(to: toolbar, in: screen, side: side, presetCount: count)
                XCTAssertEqual(panel.width, min(base.width, expected))
                if side.isHorizontal {
                    let area = DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen, side: side)
                    XCTAssertEqual(panel.height, area.height)
                    XCTAssertEqual(side == .top ? panel.maxY : panel.minY, side == .top ? toolbar.minY : toolbar.maxY)
                } else {
                    XCTAssertEqual(panel.height, base.height)
                    XCTAssertEqual(panel.minY, base.minY)
                }
                XCTAssertEqual(side == .right ? panel.maxX : panel.minX, side == .right ? base.maxX : base.minX)
                XCTAssertTrue(screen.contains(panel))
            }
        }
    }

    func testResolutionPanelSpansFullEdgeHeightOnEveryDock() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        for side in [ToolbarSide.left, .right] {
            let toolbar = side == .right ? CGRect(x: 1860, y: 300, width: 60, height: 400) : CGRect(x: 0, y: 300, width: 60, height: 400)
            let panel = DesktopToolbarLayout.resolutionPanel(to: toolbar, in: screen, side: side, presetCount: 7)
            XCTAssertEqual(panel.minY, toolbar.minY); XCTAssertEqual(panel.maxY, toolbar.maxY)
        }
    }

    func testResolutionPanelRemainsInsideNarrowDesktop() {
        let screen = CGRect(x: 50, y: -300, width: 400, height: 600)
        for side in ToolbarSide.allCases {
            let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 3, side: side)
            let base = DesktopToolbarLayout.expandedPanel(to: toolbar, in: screen, side: side)
            let panel = DesktopToolbarLayout.resolutionPanel(to: toolbar, in: screen, side: side, presetCount: 12)
            XCTAssertLessThanOrEqual(panel.width, base.width)
            XCTAssertTrue(screen.contains(panel))
        }
    }

    func testGridNeverLosesOrDuplicatesPresetsAtNarrowWidths() {
        for count in 0...40 {
            for columns in 1...3 {
                for side in ToolbarSide.allCases {
                    let slots = ReachablePresetGrid.slots(count: count, columns: columns, side: side)
                    XCTAssertEqual(slots.compactMap { $0 }.sorted(), Array(0..<count))
                }
            }
        }
    }
}
