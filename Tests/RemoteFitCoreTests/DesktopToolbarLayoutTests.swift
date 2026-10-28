import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class DesktopToolbarLayoutTests: XCTestCase {
    func testToolbarRedocksToRightEdgeAfterResolutionChange() {
        let before = CGRect(x: 0, y: 25, width: 1400, height: 605)
        let after = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let staleCenter = before.midY
        for expanded in [false, true] {
            let old = DesktopToolbarLayout.toolbar(in: before, centerY: staleCenter, expanded: expanded, count: 6, side: .right)
            let new = DesktopToolbarLayout.toolbar(in: after, centerY: staleCenter, expanded: expanded, count: 6, side: .right)
            XCTAssertNotEqual(old.maxX, new.maxX)
            XCTAssertEqual(new.maxX, after.maxX - (expanded ? 0 : DesktopToolbarLayout.margin), accuracy: 0.5)
            XCTAssertTrue(after.contains(new))
        }
    }

    func testFilledWorkspaceTouchesToolbarWithoutGapAtEveryEdge() {
        for screen in [CGRect(x: 0, y: 33, width: 1728, height: 1084), CGRect(x: -1280, y: -900, width: 1280, height: 690)] {
            for side in ToolbarSide.allCases {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 4, side: side)
                let workspace = DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen, side: side)
                XCTAssertTrue(screen.contains(workspace))
                XCTAssertFalse(workspace.intersects(toolbar))
                switch side {
                case .left: XCTAssertEqual(workspace.minX, toolbar.maxX)
                case .right: XCTAssertEqual(workspace.maxX, toolbar.minX)
                case .top: XCTAssertEqual(workspace.maxY, toolbar.minY)
                case .bottom: XCTAssertEqual(workspace.minY, toolbar.maxY)
                }
                if side.isHorizontal { XCTAssertEqual(workspace.height + toolbar.height, screen.height) }
                else { XCTAssertEqual(workspace.width + toolbar.width, screen.width) }
            }
        }
    }

    func testVerticalToolbarStaysOneFixedColumnAndPagesOverflow() {
        let short = CGRect(x: 0, y: 0, width: 1280, height: 690)
        let tall = CGRect(x: 0, y: 0, width: 1280, height: 1084)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: short, count: 4).columns, 1)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: tall, count: 10).columns, 1)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: short, count: 10).columns, 1)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: short, count: 10).rows, 8)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: short, count: 10).pages, 2)
        XCTAssertEqual(DesktopToolbarLayout.grid(in: tall, count: 10).pages, 1)
        XCTAssertEqual(DesktopToolbarLayout.toolbar(in: short, centerY: 345, expanded: true, count: 10).width, 72)
        XCTAssertEqual(DesktopToolbarLayout.toolbar(in: tall, centerY: 542, expanded: true, count: 10).width, 72)
    }

    func testLeftToolbarAndPanelsMirrorRightLayoutOnOffsetScreen() {
        let screen = CGRect(x: -1280, y: 33, width: 1280, height: 690)
        for expanded in [true] {
            let left = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: expanded, count: 10, side: .left)
            let right = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: expanded, count: 10)
            XCTAssertEqual(left.minX, screen.minX)
            XCTAssertEqual(left.size, right.size)
            XCTAssertEqual(left.minY, right.minY)
            let apps = DesktopToolbarLayout.applications(to: left, in: screen, side: .left)
            XCTAssertEqual(apps.minX, left.maxX)
            XCTAssertEqual(apps.width, screen.width * 0.8)
            XCTAssertEqual(DesktopToolbarLayout.applications(to: right, in: screen).width, apps.width)
            let panel = DesktopToolbarLayout.companion(to: left, in: screen, side: .left)
            XCTAssertEqual(panel.minX, left.maxX + 8)
            XCTAssertTrue(screen.contains(panel))
            XCTAssertFalse(panel.intersects(left))
        }
    }

    func testToolbarPositionDefaultsRightAndPersistsLeft() throws {
        var prefs = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(prefs.toolbarSide, .right)
        prefs.toolbarSide = .left
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs)).toolbarSide, .left)
    }
    func testCollapsedHandleRemainsAtRightEdge() {
        let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let frame = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: false, count: 8)
        XCTAssertEqual(frame.width, DesktopToolbarLayout.collapsedSize)
        XCTAssertEqual(frame.height, DesktopToolbarLayout.collapsedSize)
        XCTAssertEqual(frame.maxX, screen.maxX - 8)
        XCTAssertEqual(frame.minY, screen.minY + 8)
    }

    func testTooManyActionsPageInOneColumn() {
        let screen = CGRect(x: 0, y: 0, width: 630, height: 350)
        let frame = DesktopToolbarLayout.toolbar(in: screen, centerY: 2000, expanded: true, count: 30)
        XCTAssertTrue(screen.contains(frame))
        let grid = DesktopToolbarLayout.grid(in: screen, count: 30)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.pages, 10)
        XCTAssertEqual(frame.height, 350)
        XCTAssertEqual(frame.width, 72)
    }

    func testCompanionStaysLeftOfToolbarAndInsidePortraitScreen() {
        let screen = CGRect(x: 0, y: 33, width: 512, height: 1100)
        let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: -100, expanded: true, count: 6)
        let panel = DesktopToolbarLayout.companion(to: toolbar, in: screen)
        XCTAssertTrue(screen.contains(toolbar))
        XCTAssertTrue(screen.contains(panel))
        XCTAssertEqual(toolbar.minX - panel.maxX, 8)
        XCTAssertFalse(toolbar.intersects(panel))
    }

    func testNegativeOriginScreenAndVeryNarrowScreen() {
        for screen in [CGRect(x: -1920, y: -900, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 320, height: 400)] {
            let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.maxY + 50, expanded: true, count: 3)
            let panel = DesktopToolbarLayout.companion(to: toolbar, in: screen)
            XCTAssertTrue(screen.contains(toolbar))
            XCTAssertTrue(screen.contains(panel))
            XCTAssertEqual(toolbar.minX - panel.maxX, 8)
        }
    }

    func testTenActionsPageInOneColumnOnLandscapeDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 690)
        let grid = DesktopToolbarLayout.grid(in: screen, count: 10)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.rows, 8)
        XCTAssertEqual(grid.pages, 2)
        XCTAssertEqual(DesktopToolbarLayout.toolbar(in: screen, centerY: 345, expanded: true, count: 10).size,
                       CGSize(width: 72, height: 690))
        let moved = DesktopToolbarLayout.toolbar(in: screen, centerY: -1000, expanded: true, count: 10)
        XCTAssertEqual(moved.minY, screen.minY)
        XCTAssertEqual(moved.maxY, screen.maxY)
    }

    func testApplicationPanelMatchesToolbarAndExpandsEightyPercentAtEveryDockEdge() {
        for screen in [CGRect(x: 0, y: 33, width: 1728, height: 1084),
                       CGRect(x: -1280, y: -900, width: 1280, height: 690),
                       CGRect(x: 0, y: 0, width: 603, height: 1156)] {
            for side in ToolbarSide.allCases {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 10, side: side)
                let panel = DesktopToolbarLayout.applications(to: toolbar, in: screen, side: side)
                if side.isHorizontal {
                    XCTAssertEqual(panel.minX, toolbar.minX)
                    XCTAssertEqual(panel.maxX, toolbar.maxX)
                    XCTAssertEqual(panel.height, screen.height * 0.8, accuracy: 0.001)
                } else {
                    XCTAssertEqual(panel.minY, toolbar.minY)
                    XCTAssertEqual(panel.maxY, toolbar.maxY)
                    XCTAssertEqual(panel.width, screen.width * 0.8, accuracy: 0.001)
                }
                XCTAssertTrue(screen.contains(panel))
                XCTAssertFalse(panel.intersects(toolbar))
            }
        }
    }

    func testApplicationPanelShowsMoreThanSixColumnsOnDesktop() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 10)
        let panel = DesktopToolbarLayout.applications(to: toolbar, in: screen)
        // The launcher's 16 pt padding and 64 pt tiles with 8 pt gaps.
        let columns = Int((panel.width - 32 + 8) / 72)
        let rows = Int((panel.height - 32 + 8) / 72)
        XCTAssertGreaterThan(columns, 6)
        XCTAssertGreaterThanOrEqual(columns * rows, 150)
    }

    func testHalfWidthPanelsStayAnchoredOnNarrowAndOffsetScreens() {
        for screen in [CGRect(x: 0, y: 0, width: 512, height: 1100), CGRect(x: -1920, y: -900, width: 1920, height: 1080)] {
            for side: ToolbarSide in [.left, .right] {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 3, side: side)
                let panel = DesktopToolbarLayout.expandedPanel(to: toolbar, in: screen, side: side)
                XCTAssertTrue(screen.contains(panel))
                XCTAssertFalse(panel.intersects(toolbar))
                XCTAssertEqual(side == .right ? toolbar.minX - panel.maxX : panel.minX - toolbar.maxX, 0)
                XCTAssertLessThan(panel.width, screen.width / 2)
            }
        }
    }
    func testExpandedToolbarSpansDesktopAndCollapsedBallKeepsItsAnchor() {
        for screen in [CGRect(x: 0, y: 33, width: 1280, height: 690), CGRect(x: -1280, y: -900, width: 1280, height: 1080)] {
            for side in ToolbarSide.allCases {
                for count in [0, 2, 10, 200] {
                    for center in [-2000.0, 300.0, 4000.0] {
                        let expanded = DesktopToolbarLayout.toolbar(in: screen, centerY: center, expanded: true, count: count, side: side, centerX: center)
                        XCTAssertTrue(screen.contains(expanded))
                        if side.isHorizontal {
                            XCTAssertEqual(expanded.minX, screen.minX)
                            XCTAssertEqual(expanded.maxX, screen.maxX)
                        } else {
                            XCTAssertEqual(expanded.minY, screen.minY)
                            XCTAssertEqual(expanded.maxY, screen.maxY)
                        }
                        let ball = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY - 40, expanded: false, count: count, side: side, centerX: screen.midX + 100)
                        XCTAssertEqual(ball.size, CGSize(width: 52, height: 52))
                        XCTAssertEqual(ball.maxX, screen.maxX - 8)
                        XCTAssertEqual(ball.minY, screen.minY + 8)
                    }
                }
            }
        }
    }

    func testAllDockPositionsPersistAndLegacyDefaultRemainsRight() throws {
        XCTAssertEqual(ToolbarSide.allCases.count, 4)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).toolbarSide, .right)
        for side in ToolbarSide.allCases {
            var prefs = Preferences()
            prefs.toolbarSide = side
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs)).toolbarSide, side)
        }
    }

    func testFourPositionsKeepTheirDockEdgeWhenExpanding() {
        let screen = CGRect(x: -1280, y: 33, width: 1280, height: 690)
        for side in ToolbarSide.allCases {
            let ball = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY - 40, expanded: false, count: 2, side: side, centerX: screen.midX + 100)
            let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: ball.midY, expanded: true, count: 2, side: side, centerX: ball.midX)
            XCTAssertTrue(screen.contains(toolbar))
            switch side {
            case .left: XCTAssertEqual(toolbar.minX, screen.minX)
            case .right: XCTAssertEqual(toolbar.maxX, screen.maxX)
            case .top: XCTAssertEqual(toolbar.maxY, screen.maxY)
            case .bottom: XCTAssertEqual(toolbar.minY, screen.minY)
            }
            if side.isHorizontal {
                XCTAssertEqual(toolbar.minX, screen.minX)
                XCTAssertEqual(toolbar.maxX, screen.maxX)
            } else {
                XCTAssertEqual(toolbar.minY, screen.minY)
                XCTAssertEqual(toolbar.maxY, screen.maxY)
            }
        }
    }

    func testHorizontalToolbarClampsAndPagesOnPortraitAndOffsetScreens() {
        for screen in [CGRect(x: 0, y: 33, width: 512, height: 1100), CGRect(x: -1280, y: -900, width: 1280, height: 690)] {
            for side: ToolbarSide in [.top, .bottom] {
                for center in [screen.minX - 1000, screen.midX, screen.maxX + 1000] {
                    let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 200, side: side, centerX: center)
                    let grid = DesktopToolbarLayout.grid(in: screen, count: 200, side: side)
                    XCTAssertTrue(screen.contains(toolbar))
                    XCTAssertGreaterThan(grid.pages, 1)
                    XCTAssertGreaterThanOrEqual(grid.capacity * grid.pages, 200)
                    XCTAssertLessThanOrEqual(CGFloat(grid.columns) * 64 + 8 + grid.horizontalFooterWidth, toolbar.width)
                    XCTAssertLessThanOrEqual(CGFloat(grid.rows - 1) * 64 + 58, toolbar.height - 16)
                }
            }
        }
    }

    func testCompanionPanelsAndWorkspaceStayInwardForEveryDockEdge() {
        for screen in [CGRect(x: 0, y: 33, width: 512, height: 1100), CGRect(x: -1280, y: -900, width: 1280, height: 690)] {
            for side in ToolbarSide.allCases {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 10, side: side)
                let resolution = DesktopToolbarLayout.expandedPanel(to: toolbar, in: screen, side: side)
                let apps = DesktopToolbarLayout.applications(to: toolbar, in: screen, side: side)
                let companion = DesktopToolbarLayout.companion(to: toolbar, in: screen, side: side)
                let workspace = DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen, side: side)
                for rect in [resolution, apps, companion, workspace] {
                    XCTAssertTrue(screen.contains(rect), "\(side): \(rect)")
                    XCTAssertFalse(rect.intersects(toolbar))
                }
                switch side {
                case .left: XCTAssertEqual(apps.minX - toolbar.maxX, 0)
                case .right: XCTAssertEqual(toolbar.minX - apps.maxX, 0)
                case .top: XCTAssertEqual(toolbar.minY - apps.maxY, 0)
                case .bottom: XCTAssertEqual(apps.minY - toolbar.maxY, 0)
                }
            }
        }
    }
    func testFooterIsSingleColumn() {
        XCTAssertEqual(DesktopToolbarLayout.fixedButtonCount, 3)
        XCTAssertEqual(DesktopToolbarLayout.sideWidth, 72)
        XCTAssertEqual(DesktopToolbarLayout.footerHeight(), 3 * 42 + 8)
        XCTAssertEqual(DesktopToolbarLayout.footerHeight(windowControls: true), 4 * 42 + 8)
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 690)
        let grid = DesktopToolbarLayout.grid(in: screen, count: 4, side: .top, windowControls: true)
        XCTAssertEqual(grid.horizontalFooterWidth, 4 * 42 + 8)
    }

    func testApplicationPanelClampsToWorkspaceOnTinyDisplays() {
        for screen in [CGRect(x: -300, y: -200, width: 300, height: 240),
                       CGRect(x: 0, y: 33, width: 512, height: 280)] {
            for side in ToolbarSide.allCases {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: 4, side: side)
                let panel = DesktopToolbarLayout.applications(to: toolbar, in: screen, side: side)
                XCTAssertTrue(screen.contains(panel))
                XCTAssertFalse(panel.intersects(toolbar))
                if side.isHorizontal {
                    XCTAssertEqual(panel.width, toolbar.width)
                    XCTAssertLessThanOrEqual(panel.height, screen.height * 0.8)
                } else {
                    XCTAssertLessThanOrEqual(panel.width, screen.width * 0.8)
                    XCTAssertEqual(panel.height, toolbar.height)
                }
                XCTAssertGreaterThan(panel.width, 0)
                XCTAssertGreaterThan(panel.height, 0)
            }
        }
    }


}

final class ToolbarWorkspacePresenceTests: XCTestCase {
    func testHiddenAndCollapsedToolbarLeaveWholeScreenToWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        for side in ToolbarSide.allCases {
            let toolbar: CGRect = switch side {
            case .right: CGRect(x: 1380, y: 200, width: 60, height: 400)
            case .left: CGRect(x: 0, y: 200, width: 60, height: 400)
            case .top: CGRect(x: 300, y: 815, width: 600, height: 60)
            case .bottom: CGRect(x: 300, y: 0, width: 600, height: 60)
            }
            XCTAssertEqual(DesktopToolbarLayout.workspace(presence: .hidden, toolbar: toolbar, in: screen, side: side), screen, "\(side)")
            XCTAssertEqual(DesktopToolbarLayout.workspace(presence: .collapsed, toolbar: toolbar, in: screen, side: side), screen, "\(side)")
            let expanded = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: toolbar, in: screen, side: side)
            XCTAssertEqual(expanded, DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen, side: side))
            XCTAssertFalse(expanded.intersects(toolbar.insetBy(dx: 1, dy: 1)), "\(side)")
        }
    }

    func testShadowWindowKeepsRoomOnlyInsideTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 51, width: 1138, height: 970)
        let right = CGRect(x: 1066, y: 51, width: 72, height: 970)
        XCTAssertEqual(DesktopToolbarLayout.shadowWindow(around: right, padding: 16, in: visible), CGRect(x: 1050, y: 51, width: 88, height: 970))
        let top = CGRect(x: 0, y: 947, width: 1138, height: 74)
        XCTAssertEqual(DesktopToolbarLayout.shadowWindow(around: top, padding: 16, in: visible), CGRect(x: 0, y: 931, width: 1138, height: 90))
        let floating = CGRect(x: 500, y: 500, width: 52, height: 52)
        XCTAssertEqual(DesktopToolbarLayout.shadowWindow(around: floating, padding: 16, in: visible), floating.insetBy(dx: -16, dy: -16))
        // The glass itself is never clipped, even if it sticks out of the visible frame.
        let outside = CGRect(x: 1100, y: 30, width: 52, height: 52)
        XCTAssertTrue(DesktopToolbarLayout.shadowWindow(around: outside, padding: 16, in: visible).contains(outside))
    }
}
