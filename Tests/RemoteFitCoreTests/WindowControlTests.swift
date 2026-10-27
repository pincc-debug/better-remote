import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class WindowControlTests: XCTestCase {
    typealias C = WindowControlTarget.Candidate

    func testPrefersFocusedThenMainThenFirstOrdinaryWindow() {
        XCTAssertEqual(WindowControlTarget.select([C(), C(main: true), C(focused: true)]), 2)
        XCTAssertEqual(WindowControlTarget.select([C(), C(main: true)]), 1)
        XCTAssertEqual(WindowControlTarget.select([C(minimized: true), C(usable: false), C()]), 2)
    }

    func testSkipsMinimizedOrTinyFocusedWindow() {
        XCTAssertEqual(WindowControlTarget.select([C(focused: true, minimized: true), C(main: true)]), 1)
        XCTAssertEqual(WindowControlTarget.select([C(focused: true, usable: false), C()]), 1)
        XCTAssertNil(WindowControlTarget.select([C(minimized: true), C(usable: false)]))
        XCTAssertNil(WindowControlTarget.select([]))
    }

    func testMethodFallbacks() {
        func m(_ c: WindowControl, close: Bool = true, min: Bool = true, setMin: Bool = true, fs: Bool = true, zoom: Bool = true) -> WindowControlTarget.Method {
            WindowControlTarget.method(for: c, hasCloseButton: close, hasMinimizeButton: min, canSetMinimized: setMin, canSetFullScreen: fs, hasZoomButton: zoom)
        }
        XCTAssertEqual(m(.close), .press("AXCloseButton"))
        XCTAssertEqual(m(.close, close: false), .commandW)
        XCTAssertEqual(m(.minimize), .press("AXMinimizeButton"))
        XCTAssertEqual(m(.minimize, min: false), .setMinimized)
        XCTAssertEqual(m(.minimize, min: false, setMin: false), .unavailable)
        XCTAssertEqual(m(.fullScreen), .toggleFullScreen)
        XCTAssertEqual(m(.fullScreen, fs: false), .press("AXZoomButton"))
        XCTAssertEqual(m(.fullScreen, fs: false, zoom: false), .unavailable)
    }

    func testTitlesAndDefaults() {
        XCTAssertEqual(WindowControl.allCases.map(\.title), ["关闭", "最小化", "全屏"])
        XCTAssertTrue(Preferences().showWindowControls)
        let legacy = try! JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.showWindowControls)
    }

    func testToolbarStaysOneColumnOrRowAndPages() {
        let screens = [CGRect(x: 0, y: 0, width: 1728, height: 1084), CGRect(x: 0, y: 0, width: 1156, height: 1219),
                       CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 0, y: 0, width: 600, height: 500)]
        for screen in screens {
            for side in ToolbarSide.allCases {
                for controls in [true, false] {
                    for count in [1, 9, 30, 80] {
                        let grid = DesktopToolbarLayout.grid(in: screen, count: count, side: side, windowControls: controls)
                        let toolbar = DesktopToolbarLayout.toolbar(in: screen, centerY: screen.midY, expanded: true, count: count, side: side, windowControls: controls)
                        let label = "\(screen) \(side) \(controls) \(count)"
                        XCTAssertTrue(screen.contains(toolbar), label)
                        XCTAssertGreaterThanOrEqual(grid.capacity * grid.pages, count, label)
                        XCTAssertLessThan(grid.capacity * (grid.pages - 1), count, label)
                        XCTAssertEqual(grid.showsPageArrows, grid.pages > 1, label)
                        if side.isHorizontal {
                            XCTAssertEqual(grid.rows, 1, label)
                            XCTAssertEqual(toolbar.height, DesktopToolbarLayout.horizontalHeight, label)
                            let arrows = grid.showsPageArrows ? DesktopToolbarLayout.pageArrowLength : 0
                            XCTAssertLessThanOrEqual(CGFloat(grid.columns) * 64 - 6 + arrows + 16 + grid.horizontalFooterWidth,
                                                     toolbar.width, label)
                        } else {
                            XCTAssertEqual(grid.columns, 1, label)
                            XCTAssertEqual(toolbar.width, DesktopToolbarLayout.sideWidth, label)
                            let arrows = grid.showsPageArrows ? DesktopToolbarLayout.pageArrowLength : 0
                            XCTAssertLessThanOrEqual(CGFloat(grid.rows) * 64 - 6 + arrows + DesktopToolbarLayout.chromeHeight(columns: 1, windowControls: controls),
                                                     toolbar.height, label)
                        }
                    }
                }
            }
        }
    }

    func testPageRanges() {
        let grid = DesktopToolbarLayout.grid(in: CGRect(x: 0, y: 0, width: 1728, height: 1084), count: 30, side: .right, windowControls: true)
        XCTAssertGreaterThan(grid.pages, 1)
        XCTAssertEqual(grid.range(page: 0, count: 30), 0..<grid.capacity)
        XCTAssertEqual(grid.range(page: grid.pages - 1, count: 30).upperBound, 30)
        XCTAssertEqual(grid.range(page: 99, count: 30), grid.range(page: grid.pages - 1, count: 30))
        let few = DesktopToolbarLayout.grid(in: CGRect(x: 0, y: 0, width: 1728, height: 1084), count: 5, side: .right, windowControls: true)
        XCTAssertEqual(few.pages, 1)
        XCTAssertFalse(few.showsPageArrows)
    }

    func testWindowButtonAddsOneFooterSlot() {
        XCTAssertEqual(DesktopToolbarLayout.footerHeight(windowControls: true) - DesktopToolbarLayout.footerHeight(), DesktopToolbarLayout.footerStep)
    }

}

final class WindowSnapTests: XCTestCase {
    let area = CGRect(x: 0, y: 25, width: 1728, height: 1050)

    func testHalvesAndFill() {
        let w = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(WindowSnap.fill.frame(current: w, in: area), area)
        XCTAssertEqual(WindowSnap.left.frame(current: w, in: area), CGRect(x: 0, y: 25, width: 864, height: 1050))
        XCTAssertEqual(WindowSnap.right.frame(current: w, in: area), CGRect(x: 864, y: 25, width: 864, height: 1050))
        XCTAssertEqual(WindowSnap.top.frame(current: w, in: area), CGRect(x: 0, y: 25, width: 1728, height: 525))
        XCTAssertEqual(WindowSnap.bottom.frame(current: w, in: area), CGRect(x: 0, y: 550, width: 1728, height: 525))
        let odd = CGRect(x: 10, y: 0, width: 1001, height: 701)
        XCTAssertEqual(WindowSnap.right.frame(current: w, in: odd).maxX, odd.maxX)
        XCTAssertEqual(WindowSnap.bottom.frame(current: w, in: odd).maxY, odd.maxY)
    }

    func testCenterIsSeventyByEightyPercent() {
        let small = WindowSnap.center.frame(current: CGRect(x: 0, y: 0, width: 800, height: 600), in: area)
        XCTAssertEqual(small.size, CGSize(width: 1210, height: 840))
        XCTAssertEqual(small.midX, area.midX, accuracy: 1)
        XCTAssertEqual(small.midY, area.midY, accuracy: 1)
        let big = WindowSnap.center.frame(current: CGRect(x: 0, y: 0, width: 3000, height: 600), in: area)
        XCTAssertEqual(big.size, CGSize(width: 1210, height: 840))
        XCTAssertTrue(area.contains(big))
    }

    func testCoordinateFlipAndScreenChoice() {
        // Primary 1728 × 1117 with menu bar; visible frame in AppKit coordinates.
        let visible = CGRect(x: 0, y: 70, width: 1728, height: 1014)
        XCTAssertEqual(WindowSnap.accessibilityRect(visible, primaryScreenHeight: 1117), CGRect(x: 0, y: 33, width: 1728, height: 1014))
        let screens = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1728, y: 0, width: 1920, height: 1080)]
        XCTAssertEqual(WindowSnap.screenIndex(for: CGRect(x: 1600, y: 100, width: 600, height: 400), screens: screens), 1)
        XCTAssertEqual(WindowSnap.screenIndex(for: CGRect(x: 100, y: 100, width: 600, height: 400), screens: screens), 0)
        XCTAssertEqual(WindowSnap.screenIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), screens: screens), 0)
        XCTAssertNil(WindowSnap.screenIndex(for: .zero, screens: []))
        XCTAssertEqual(WindowSnap.allCases.map(\.title), ["填充", "左半屏", "右半屏", "上半屏", "下半屏", "居中"])
    }

    func testFlyoutSitsBesideButtonInsideScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let toolbar = CGRect(x: 1628, y: 0, width: 100, height: 1084)
        let button = CGRect(x: 1680, y: 10, width: 44, height: 44)
        let right = DesktopToolbarLayout.flyout(beside: button, toolbar: toolbar, in: screen, size: CGSize(width: 280, height: 200), side: .right)
        XCTAssertEqual(right.maxX, toolbar.minX - 8)
        XCTAssertTrue(screen.contains(right))
        let left = DesktopToolbarLayout.flyout(beside: CGRect(x: 4, y: 500, width: 44, height: 44), toolbar: CGRect(x: 0, y: 0, width: 100, height: 1084),
                                               in: screen, size: CGSize(width: 280, height: 200), side: .left)
        XCTAssertEqual(left.minX, 108)
        XCTAssertEqual(left.midY, 522)
        let bottom = DesktopToolbarLayout.flyout(beside: CGRect(x: 800, y: 20, width: 44, height: 44), toolbar: CGRect(x: 0, y: 0, width: 1728, height: 104),
                                                 in: screen, size: CGSize(width: 280, height: 200), side: .bottom)
        XCTAssertEqual(bottom.minY, 112)
    }
}

final class WindowTilingTests: XCTestCase {
    let area = CGRect(x: 0, y: 33, width: 1728, height: 1050)

    func covers(_ frames: [CGRect]) {
        let total = frames.reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(total, area.width * area.height, accuracy: 1)
        for (i, a) in frames.enumerated() {
            XCTAssertTrue(area.contains(a))
            for b in frames[(i + 1)...] { XCTAssertTrue(a.intersection(b).isEmpty || a.intersection(b).width * a.intersection(b).height == 0) }
        }
    }

    func testSmallCounts() {
        XCTAssertEqual(WindowTiling.frames(count: 0, in: area), [])
        XCTAssertEqual(WindowTiling.frames(count: 1, in: area), [area])
        let two = WindowTiling.frames(count: 2, in: area)
        XCTAssertEqual(two, [CGRect(x: 0, y: 33, width: 864, height: 1050), CGRect(x: 864, y: 33, width: 864, height: 1050)])
        let three = WindowTiling.frames(count: 3, in: area)
        XCTAssertEqual(three[0], CGRect(x: 0, y: 33, width: 864, height: 1050))
        XCTAssertEqual(three[1], CGRect(x: 864, y: 33, width: 864, height: 525))
        XCTAssertEqual(three[2], CGRect(x: 864, y: 558, width: 864, height: 525))
        let four = WindowTiling.frames(count: 4, in: area)
        XCTAssertTrue(four.allSatisfy { $0.size == CGSize(width: 864, height: 525) })
        [two, three, four].forEach(covers)
    }

    func testBalancedGridForFivePlus() {
        for n in 5...12 {
            let frames = WindowTiling.frames(count: n, in: area)
            XCTAssertEqual(frames.count, n)
            covers(frames)
        }
        let five = WindowTiling.frames(count: 5, in: area)
        XCTAssertEqual(five.filter { $0.minY == area.minY }.count, 3)
        XCTAssertEqual(five.last?.maxX, area.maxX)
    }

    func testEligibility() {
        let screen = area
        XCTAssertTrue(WindowTiling.eligible(CGRect(x: 10, y: 50, width: 600, height: 400), on: screen, minimized: false, isOwn: false, isStandard: true))
        XCTAssertFalse(WindowTiling.eligible(CGRect(x: 10, y: 50, width: 600, height: 400), on: screen, minimized: true, isOwn: false, isStandard: true))
        XCTAssertFalse(WindowTiling.eligible(CGRect(x: 10, y: 50, width: 600, height: 400), on: screen, minimized: false, isOwn: true, isStandard: true))
        XCTAssertFalse(WindowTiling.eligible(CGRect(x: 10, y: 50, width: 100, height: 400), on: screen, minimized: false, isOwn: false, isStandard: true))
        XCTAssertFalse(WindowTiling.eligible(CGRect(x: 3000, y: 50, width: 600, height: 400), on: screen, minimized: false, isOwn: false, isStandard: true))
        XCTAssertFalse(WindowTiling.eligible(CGRect(x: 10, y: 50, width: 600, height: 400), on: screen, minimized: false, isOwn: false, isStandard: false))
    }
}

final class ToolbarPageSizeTests: XCTestCase {
    func testPageSizeUsesAllFreeLength() {
        // Items are 58 tall on a 64 step: n items need n * 64 - 6.
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 3, length: 186).perPage, 3)
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 3, length: 186).pages, 1)
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 4, length: 186).perPage, 3) // no arrows: overflow keeps every fitting slot
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 4, length: 250).perPage, 4)
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 20, length: 700).perPage, 11)
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 20, length: 700).pages, 2)
        XCTAssertEqual(DesktopToolbarLayout.pageSize(count: 5, length: 10).perPage, 1)
    }

    func testSideToolbarFillsHeightAtSeveralResolutions() {
        // Mac, foldable inner screen, landscape phone (e.g. 1252 × 578) and portrait phone visible heights.
        for height in [1084.0, 1219.0, 545.0, 700.0, 400.0] as [CGFloat] {
            let screen = CGRect(x: 0, y: 0, width: 1252, height: height)
            for count in [3, 11, 40] {
                let grid = DesktopToolbarLayout.grid(in: screen, count: count, side: .right, windowControls: true)
                let free = height - DesktopToolbarLayout.chromeHeight(columns: 1, windowControls: true)
                let arrows = grid.showsPageArrows ? DesktopToolbarLayout.pageArrowLength : 0
                let used = CGFloat(grid.rows) * 64 - 6 + arrows
                XCTAssertLessThanOrEqual(used, max(free, 58 + arrows), "\(height) \(count)")
                if grid.pages > 1 { XCTAssertGreaterThan(used + 64, free, "page leaves a whole slot empty: \(height) \(count)") }
                else { XCTAssertEqual(grid.rows, count) }
            }
        }
        // Landscape phone: 545 visible points fit 3 custom items above the single-column fixed buttons.
        let phone = DesktopToolbarLayout.grid(in: CGRect(x: 0, y: 0, width: 1252, height: 545), count: 3, side: .right, windowControls: true)
        XCTAssertEqual(phone.pages, 1)
        XCTAssertEqual(phone.rows, 3)
    }
}

final class WindowArrangementTests: XCTestCase {
    let area = CGRect(x: 0, y: 25, width: 1728, height: 1050)
    func testTakesOnlyNeededWindows() {
        XCTAssertEqual(WindowArrangement.halves.frames(available: 5, in: area).count, 2)
        XCTAssertEqual(WindowArrangement.mainAndStack.frames(available: 9, in: area).count, 3)
        XCTAssertEqual(WindowArrangement.grid.frames(available: 7, in: area).count, 4)
    }
    func testFewerWindowsUsesWhatExists() {
        XCTAssertEqual(WindowArrangement.grid.frames(available: 1, in: area), [CGRect(x: 0, y: 25, width: 864, height: 525)])
        XCTAssertEqual(WindowArrangement.halves.frames(available: 1, in: area), [CGRect(x: 0, y: 25, width: 864, height: 1050)])
        XCTAssertEqual(WindowArrangement.mainAndStack.frames(available: 2, in: area),
                       Array(WindowArrangement.mainAndStack.frames(available: 3, in: area).prefix(2)))
        XCTAssertEqual(WindowArrangement.mainAndStack.frames(available: 2, in: area).count, 2)
        XCTAssertEqual(WindowArrangement.halves.frames(available: 0, in: area), [])
    }
    func testFrontWindowGetsLeftBigSlot() {
        let f = WindowArrangement.mainAndStack.frames(available: 3, in: area)
        XCTAssertEqual(f[0], CGRect(x: 0, y: 25, width: 864, height: 1050))
        XCTAssertEqual(f[1].height + f[2].height, 1050)
        XCTAssertEqual(f[1].minX, 864)
    }
}


final class WindowPickingTests: XCTestCase {
    func testSlotsFollowClickOrder() {
        var session = WindowPickSession<Int>(needed: 3)
        XCTAssertEqual(session.click(30), .picked(slot: 1))
        XCTAssertEqual(session.click(10), .picked(slot: 2))
        XCTAssertEqual(session.click(20), .complete)
        XCTAssertEqual(session.picked, [30, 10, 20])
        XCTAssertEqual(session.slot(of: 10), 2)
    }
    func testFrontmostPrepickedTakesSlotOne() {
        var session = WindowPickSession<Int>(needed: 3, prepicked: [7])
        XCTAssertEqual(session.slot(of: 7), 1)
        XCTAssertEqual(session.click(8), .picked(slot: 2))
        XCTAssertEqual(session.click(7), .finished)
        XCTAssertEqual(session.picked, [7, 8])
    }
    func testRepeatOrEmptyClickFinishesEarly() {
        var session = WindowPickSession<Int>(needed: 4)
        _ = session.click(1)
        XCTAssertEqual(session.click(1), .finished)
        var empty = WindowPickSession<Int>(needed: 2)
        XCTAssertEqual(empty.click(nil), .finished)
    }
    func testHitPicksFrontmostOrdinaryWindow() {
        let windows = [ScreenWindow(number: 1, pid: 9, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30), layer: 25),
                       ScreenWindow(number: 2, pid: 9, bounds: CGRect(x: 0, y: 0, width: 2000, height: 2000), layer: 0),
                       ScreenWindow(number: 3, pid: 4, bounds: CGRect(x: 100, y: 100, width: 500, height: 400), layer: 0),
                       ScreenWindow(number: 4, pid: 5, bounds: CGRect(x: 50, y: 50, width: 800, height: 600), layer: 0)]
        XCTAssertEqual(ScreenWindow.hit(CGPoint(x: 200, y: 200), in: windows, excluding: [2])?.number, 3)
        XCTAssertEqual(ScreenWindow.hit(CGPoint(x: 700, y: 600), in: windows, excluding: [2])?.number, 4)
        XCTAssertNil(ScreenWindow.hit(CGPoint(x: 1500, y: 1500), in: windows, excluding: [2]))
        XCTAssertEqual(ScreenWindow.hit(CGPoint(x: 10, y: 10), in: windows, excluding: [])?.number, 2)
    }
}

final class WindowArrangementFrameTests: XCTestCase {
    let area = CGRect(x: 0, y: 30, width: 1200, height: 690)
    private func f(_ a: WindowArrangement) -> [CGRect] { a.frames(available: a.windowCount, in: area) }
    private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    func testEveryLayoutFrames() {
        XCTAssertEqual(f(.halves), [r(0, 30, 600, 690), r(600, 30, 600, 690)])
        XCTAssertEqual(f(.verticalHalves), [r(0, 30, 1200, 345), r(0, 375, 1200, 345)])
        XCTAssertEqual(f(.mainAndStack), [r(0, 30, 600, 690), r(600, 30, 600, 345), r(600, 375, 600, 345)])
        XCTAssertEqual(f(.stackAndMain), [r(600, 30, 600, 690), r(0, 30, 600, 345), r(0, 375, 600, 345)])
        XCTAssertEqual(f(.topAndPair), [r(0, 30, 1200, 345), r(0, 375, 600, 345), r(600, 375, 600, 345)])
        XCTAssertEqual(f(.pairAndBottom), [r(0, 375, 1200, 345), r(0, 30, 600, 345), r(600, 30, 600, 345)])
        XCTAssertEqual(f(.thirds), [r(0, 30, 400, 690), r(400, 30, 400, 690), r(800, 30, 400, 690)])
        XCTAssertEqual(f(.wideLeft), [r(0, 30, 800, 690), r(800, 30, 400, 690)])
        XCTAssertEqual(f(.wideRight), [r(400, 30, 800, 690), r(0, 30, 400, 690)])
        XCTAssertEqual(f(.wideCenter), [r(300, 30, 600, 690), r(0, 30, 300, 690), r(900, 30, 300, 690)])
        XCTAssertEqual(f(.grid), [r(0, 30, 600, 345), r(600, 30, 600, 345), r(0, 375, 600, 345), r(600, 375, 600, 345)])
    }
    func testLayoutsTileWithoutGapsOrOverlap() {
        for a in WindowArrangement.allCases {
            let frames = f(a)
            XCTAssertEqual(frames.map { $0.width * $0.height }.reduce(0, +), area.width * area.height, a.title)
            for i in frames.indices { for j in frames.indices where i < j { XCTAssertFalse(frames[i].intersects(frames[j]), a.title) } }
        }
    }
    func testSlotOneIsLargest() {
        for a in WindowArrangement.allCases {
            let areas = f(a).map { $0.width * $0.height }
            XCTAssertEqual(areas[0], areas.max(), a.title)
        }
    }
}


final class LayoutCoordinateTests: XCTestCase {
    // Primary 1728×1117 (menu bar 33pt, no Dock); secondary 1920×1080 to the right, raised 200pt; third left of primary, lower.
    let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let primaryVisible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    let secondaryVisible = CGRect(x: 1728, y: 200, width: 1920, height: 1055)
    let leftVisible = CGRect(x: -1280, y: -400, width: 1280, height: 775)

    func ax(_ r: CGRect) -> CGRect { WindowSnap.accessibilityRect(r, primaryScreenHeight: primary.maxY) }

    func testAccessibilityRectFlipsAgainstPrimaryOnEveryScreen() {
        XCTAssertEqual(ax(primaryVisible), CGRect(x: 0, y: 33, width: 1728, height: 1084))
        XCTAssertEqual(ax(secondaryVisible), CGRect(x: 1728, y: 1117 - 1255, width: 1920, height: 1055))
        XCTAssertEqual(ax(leftVisible), CGRect(x: -1280, y: 1117 - 375, width: 1280, height: 775))
        // Round trip is its own inverse.
        XCTAssertEqual(ax(ax(secondaryVisible)), secondaryVisible)
    }

    func testFillAndHalvesUseTheWholeVisibleFrameOnSecondaryScreen() {
        let area = ax(secondaryVisible)
        XCTAssertEqual(WindowSnap.fill.frame(current: CGRect(x: 1800, y: 0, width: 300, height: 200), in: area), area)
        let halves = WindowArrangement.halves.frames(available: 2, in: area)
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].minX, area.minX, accuracy: 1)
        XCTAssertEqual(halves[1].maxX, area.maxX, accuracy: 1)
        XCTAssertEqual(halves[0].height, area.height, accuracy: 1)
        let vertical = WindowArrangement.verticalHalves.frames(available: 2, in: area)
        XCTAssertEqual(vertical.map(\.minY).min()!, area.minY, accuracy: 1)
        XCTAssertEqual(vertical.map(\.maxY).max()!, area.maxY, accuracy: 1)
        XCTAssertEqual(vertical[0].width, area.width, accuracy: 1)
        for arrangement in WindowArrangement.allCases {
            let union = arrangement.frames(available: arrangement.windowCount, in: area).reduce(CGRect.null) { $0.union($1) }
            XCTAssertEqual(union.minX, area.minX, accuracy: 1, "\(arrangement)"); XCTAssertEqual(union.maxX, area.maxX, accuracy: 1, "\(arrangement)")
            XCTAssertEqual(union.minY, area.minY, accuracy: 1, "\(arrangement)"); XCTAssertEqual(union.maxY, area.maxY, accuracy: 1, "\(arrangement)")
        }
    }

    func testFrontmostIsPrepickedAndPickingStartsAtSlotTwo() {
        var session = WindowPickSession<Int>(needed: 3, prepicked: [7])
        XCTAssertEqual(session.click(8), .picked(slot: 2))
        XCTAssertEqual(session.click(7), .finished)
        var two = WindowPickSession<Int>(needed: 2, prepicked: [7])
        XCTAssertEqual(two.click(9), .complete)
    }
}
