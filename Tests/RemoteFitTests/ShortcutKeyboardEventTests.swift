import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class ShortcutKeyboardEventTests: XCTestCase {
    func testControlArrowsKeepQuartzKeyIdentityOnDownAndUp() throws {
        for code: UInt16 in [123, 124, 125, 126] {
            let plan = ShortcutEventPlan.strokes(for: .init(code: code, modifiers: 1 << 18, label: "Arrow"))
            let source = CGEventSource(stateID: .privateState)
            for stroke in (plan.press + plan.release).filter({ !$0.modifier }) {
                let event = try XCTUnwrap(ShortcutSender.keyboardEvent(for: stroke, source: source))
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(code))
                XCTAssertTrue(event.flags.contains(.maskControl))
                XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
                XCTAssertTrue(event.flags.contains(.maskNumericPad))
                XCTAssertEqual(event.type, stroke.down ? .keyDown : .keyUp)
            }
            let release = try XCTUnwrap(plan.release.last)
            let event = try XCTUnwrap(ShortcutSender.keyboardEvent(for: release, source: source))
            XCTAssertEqual(event.type, .flagsChanged)
            XCTAssertFalse(event.flags.contains(.maskControl))
            XCTAssertFalse(event.flags.contains(.maskSecondaryFn))
            XCTAssertFalse(event.flags.contains(.maskNumericPad))
        }
    }

    func testFunctionAndNavigationKeysKeepFnWithoutNumericPad() throws {
        for code: UInt16 in [122, 120, 99, 115, 116, 117, 119, 121] {
            let stroke = try XCTUnwrap(ShortcutEventPlan.strokes(for: .init(code: code, modifiers: 0, label: "Key")).press.last)
            let event = try XCTUnwrap(ShortcutSender.keyboardEvent(for: stroke, source: CGEventSource(stateID: .privateState)))
            XCTAssertTrue(event.flags.contains(.maskSecondaryFn))
            XCTAssertFalse(event.flags.contains(.maskNumericPad))
        }
    }

    func testKeypadEnterRemainsDistinctFromReturn() throws {
        for code: UInt16 in [36, 76] {
            let stroke = try XCTUnwrap(ShortcutEventPlan.strokes(for: .init(code: code, modifiers: 0, label: "Enter")).press.last)
            let event = try XCTUnwrap(ShortcutSender.keyboardEvent(for: stroke, source: CGEventSource(stateID: .privateState)))
            XCTAssertEqual(event.flags.contains(.maskNumericPad), code == 76)
            XCTAssertFalse(event.flags.contains(.maskSecondaryFn))
        }
    }

    func testOrdinaryCommandKeysDoNotAcquireFnOrKeypadFlags() throws {
        for code: UInt16 in [8, 9, 49] {
            let stroke = try XCTUnwrap(ShortcutEventPlan.strokes(for: .init(code: code, modifiers: 1 << 20, label: "Key")).press.last)
            let event = try XCTUnwrap(ShortcutSender.keyboardEvent(for: stroke, source: CGEventSource(stateID: .privateState)))
            XCTAssertTrue(event.flags.contains(.maskCommand))
            XCTAssertFalse(event.flags.contains(.maskSecondaryFn))
            XCTAssertFalse(event.flags.contains(.maskNumericPad))
        }
    }
}
