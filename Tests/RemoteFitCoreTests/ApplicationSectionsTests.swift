import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class ApplicationSectionsTests: XCTestCase {
    func testOrderAndDedupe() {
        let sections = ApplicationSection.make(recent: ["a", "b"], running: ["b", "c"], all: ["a", "b", "c", "d", "e"])
        XCTAssertEqual(sections.map(\.kind), [.recent, .running, .all])
        XCTAssertEqual(sections.map(\.identifiers), [["a", "b"], ["c"], ["d", "e"]])
        XCTAssertEqual(sections.map(\.title), ["最近", "运行中", "全部"])
    }

    func testEmptySectionsAreDropped() {
        let sections = ApplicationSection.make(recent: [], running: ["a"], all: ["a"])
        XCTAssertEqual(sections.map(\.kind), [.running])
        XCTAssertTrue(ApplicationSection.make(recent: [], running: [], all: []).isEmpty)
    }

    func testEveryAppAppearsExactlyOnce() {
        let all = (0..<40).map { "app\($0)" }
        let sections = ApplicationSection.make(recent: Array(all.prefix(5)).reversed(), running: all.filter { $0.hasSuffix("3") }, all: all)
        let flat = sections.flatMap(\.identifiers)
        XCTAssertEqual(flat.count, all.count)
        XCTAssertEqual(Set(flat), Set(all))
    }

    func testScrollingPanelUsesScreenSpaceBesideToolbar() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let toolbar = CGRect(x: 1650, y: 27, width: 84, height: 1090)
        let panel = DesktopToolbarLayout.applications(to: toolbar, in: screen, side: .right)
        XCTAssertEqual(panel.maxX, toolbar.minX)
        XCTAssertEqual(panel.width, screen.width * 0.8)
        XCTAssertEqual(panel.minY, toolbar.minY)
        XCTAssertEqual(panel.maxY, toolbar.maxY)
    }

    func testScrollingPanelClampsOnSmallScreens() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 700)
        let toolbar = CGRect(x: 316, y: 0, width: 84, height: 700)
        let panel = DesktopToolbarLayout.applications(to: toolbar, in: screen, side: .right)
        XCTAssertGreaterThanOrEqual(panel.minX, screen.minX)
        XCTAssertEqual(panel.maxX, toolbar.minX)
    }
}
