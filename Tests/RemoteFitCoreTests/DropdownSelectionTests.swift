import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class DropdownSelectionTests: XCTestCase {
    func testOpenHighlightsSelectionOrFirst() {
        var state = DropdownSelection(items: ["a", "b", "c"], selected: "b")
        state.open()
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.highlighted, 1)
        var none = DropdownSelection(items: ["a", "b"], selected: nil)
        none.open()
        XCTAssertEqual(none.highlighted, 0)
        var empty = DropdownSelection<String>(items: [], selected: nil)
        empty.open()
        XCTAssertFalse(empty.isOpen)
    }

    func testArrowKeysClampWithoutWrapping() {
        var state = DropdownSelection(items: ["a", "b", "c"], selected: "a")
        state.open()
        state.moveUp(); XCTAssertEqual(state.highlighted, 0)
        state.moveDown(); state.moveDown(); state.moveDown()
        XCTAssertEqual(state.highlighted, 2)
    }

    func testArrowOnClosedMenuOpensIt() {
        var state = DropdownSelection(items: ["a", "b"], selected: "b")
        state.moveDown()
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.highlighted, 1)
    }

    func testReturnCommitsHighlightedAndReportsOnlyChanges() {
        var state = DropdownSelection(items: ["a", "b", "c"], selected: "a")
        state.open(); state.moveDown()
        XCTAssertEqual(state.commit(), "b")
        XCTAssertEqual(state.selected, "b")
        XCTAssertFalse(state.isOpen)
        state.open()
        XCTAssertNil(state.commit(), "re-choosing the current value changes nothing")
        XCTAssertEqual(state.selected, "b")
    }

    func testClickCommitsGivenRowAndHoverMovesHighlight() {
        var state = DropdownSelection(items: ["a", "b", "c"], selected: nil)
        state.open()
        state.hover(2); XCTAssertEqual(state.highlighted, 2)
        state.hover(9); XCTAssertEqual(state.highlighted, 2)
        XCTAssertEqual(state.commit(0), "a")
    }

    func testEscapeClosesWithoutChanging() {
        var state = DropdownSelection(items: ["a", "b"], selected: "a")
        state.open(); state.moveDown(); state.close()
        XCTAssertFalse(state.isOpen)
        XCTAssertNil(state.highlighted)
        XCTAssertEqual(state.selected, "a")
        XCTAssertNil(state.commit(), "commit while closed is a no-op")
    }

    func testItemsShrinkingKeepsHighlightValid() {
        var state = DropdownSelection(items: ["a", "b", "c"], selected: "c")
        state.open()
        state.update(items: ["a"], selected: nil)
        XCTAssertEqual(state.highlighted, 0)
    }

    func testKeyCodes() {
        XCTAssertEqual(DropdownKey(keyCode: 126), .up)
        XCTAssertEqual(DropdownKey(keyCode: 125), .down)
        XCTAssertEqual(DropdownKey(keyCode: 36), .commit)
        XCTAssertEqual(DropdownKey(keyCode: 76), .commit)
        XCTAssertEqual(DropdownKey(keyCode: 49), .commit)
        XCTAssertEqual(DropdownKey(keyCode: 53), .cancel)
        XCTAssertNil(DropdownKey(keyCode: 0))
    }

    func testMenuOpensBelowAndFlipsAboveWhenNoRoom() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 120, height: 200)
        let high = CGRect(x: 100, y: 600, width: 160, height: 28)
        let below = DropdownSelection<String>.menuFrame(trigger: high, size: size, gap: 4, bounds: screen)
        XCTAssertEqual(below, CGRect(x: 100, y: 396, width: 160, height: 200), "below, at least trigger width")
        let low = CGRect(x: 100, y: 60, width: 160, height: 28)
        XCTAssertEqual(DropdownSelection<String>.edge(trigger: low, menuHeight: 200, gap: 4, bounds: screen), .above)
        XCTAssertEqual(DropdownSelection<String>.menuFrame(trigger: low, size: size, gap: 4, bounds: screen).minY, 92)
    }

    func testMenuStaysInsideScreenHorizontally() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let trigger = CGRect(x: 950, y: 500, width: 40, height: 28)
        let frame = DropdownSelection<String>.menuFrame(trigger: trigger, size: CGSize(width: 200, height: 100), gap: 4, bounds: screen)
        XCTAssertEqual(frame.maxX, 1000)
    }

    func testMenuIsNeverNarrowerThanTrigger() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let trigger = CGRect(x: 100, y: 500, width: 260, height: 28)
        let narrow = DropdownSelection<String>.menuFrame(trigger: trigger, size: CGSize(width: 120, height: 100), gap: 4, bounds: screen)
        XCTAssertEqual(narrow.width, 260)
        let wide = DropdownSelection<String>.menuFrame(trigger: trigger, size: CGSize(width: 300, height: 100), gap: 4, bounds: screen)
        XCTAssertEqual(wide.width, 300)
    }
}
