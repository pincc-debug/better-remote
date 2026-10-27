import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class ShortcutSenderTests: XCTestCase {
    private let copy = NamedShortcut(name: "Copy", key: .init(code: 8, modifiers: 1 << 20, label: "C"))
    private let paste = NamedShortcut(name: "Paste", key: .init(code: 9, modifiers: 1 << 20, label: "V"))

    func testReturnCursorRecoveryFollowsKeyUp() async {
        var events: [ShortcutStroke] = []
        var targets: [pid_t?] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in },
            eventSink: { strokes, _ in events += strokes }, cursorRecovery: { target in
                XCTAssertEqual(events.map(\.down), [true, false])
                targets.append(target)
            })
        sender.enqueueTap(.init(name: "Return", key: .init(code: 36, modifiers: 0, label: "Return")), targetPID: 111)
        await sender.waitForPendingTap()
        XCTAssertEqual(targets, [111])
    }

    func testCancellationAfterReturnKeyUpCancelsCursorRecovery() async throws {
        var events: [ShortcutStroke] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in },
            eventSink: { strokes, _ in events += strokes }, cursorRecovery: { _ in XCTFail("Cancelled gesture must not restore cursor") })
        sender.enqueueTap(.init(name: "Return", key: .init(code: 36, modifiers: 0, label: "Return")), targetPID: 111)
        try await wait { events.count == 2 }
        sender.releaseAll()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(events.map(\.down), [true, false])
    }

    func testOtherShortcutsDoNotRestoreCursor() async {
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in },
            eventSink: { _, _ in }, cursorRecovery: { _ in XCTFail("Only plain Return restores cursor") })
        sender.enqueueTap(copy)
        sender.enqueueTap(.init(name: "Command Return", key: .init(code: 36, modifiers: 1 << 20, label: "Return")))
        await sender.waitForPendingTap()
    }

    func testCursorRecoveryIsStationaryMoveNotClick() throws {
        let point = CGPoint(x: 321, y: 654)
        let event = try XCTUnwrap(ShortcutSender.cursorRecoveryEvent(at: point))
        XCTAssertEqual(event.type, .mouseMoved)
        XCTAssertEqual(event.location, point)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaX), 0)
        XCTAssertEqual(event.getIntegerValueField(.mouseEventDeltaY), 0)
    }

    func testQueuedClicksWaitForFocusAndKeepTheirPressInterval() async throws {
        var unblock: CheckedContinuation<Void, Never>?
        var events: [ShortcutStroke] = []
        var pressedAt: ContinuousClock.Instant?
        var intervals: [Duration] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in
            await withCheckedContinuation { unblock = $0 }
        }, eventSink: { strokes, tap in
            XCTAssertEqual(tap, .cgSessionEventTap)
            for stroke in strokes where !stroke.modifier {
                if stroke.down { pressedAt = .now }
                else if let pressedAt { intervals.append(pressedAt.duration(to: .now)) }
            }
            events += strokes
        })
        sender.targetPID = { nil }
        sender.enqueueTap(copy)
        try await wait { unblock != nil }
        XCTAssertTrue(events.isEmpty)
        unblock?.resume(); unblock = nil
        try await wait { events.contains { !$0.modifier && !$0.down } }
        XCTAssertEqual(intervals.count, 1)
        XCTAssertTrue(intervals.allSatisfy { $0 >= .milliseconds(30) })
        XCTAssertEqual(events.last?.flags, 0)
        sender.releaseAll()
    }

    func testApplicationShortcutUsesExplicitTargetInsteadOfWindowFallback() async {
        var targets: [pid_t?] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { targets.append($0) }, eventSink: { _, _ in })
        sender.targetPID = { 111 }
        sender.enqueueTap(copy, targetPID: 222)
        await sender.waitForPendingTap()
        XCTAssertEqual(targets, [222])
    }

    func testRapidClicksRemainFIFO() async throws {
        var keys: [UInt16] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in }, eventSink: { strokes, _ in
            keys += strokes.filter { !$0.modifier }.map(\.code)
        })
        sender.targetPID = { nil }
        sender.enqueueTap(copy); sender.enqueueTap(paste)
        try await wait { keys.count == 4 }
        XCTAssertEqual(keys, [8, 8, 9, 9])
        sender.releaseAll()
    }

    func testCancellationBeforeActivationPostsNothing() async throws {
        var unblock: CheckedContinuation<Void, Never>?
        var posted = false
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in
            await withCheckedContinuation { unblock = $0 }
        }, eventSink: { _, _ in posted = true })
        sender.targetPID = { nil }
        sender.enqueueTap(copy)
        try await wait { unblock != nil }
        sender.releaseAll()
        unblock?.resume()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(posted)
    }

    func testCancellationDuringPressReleasesExactlyOnce() async throws {
        var events: [ShortcutStroke] = []
        let sender = ShortcutSender(permissionCheck: { true }, activationRequest: { _ in }, eventSink: { strokes, _ in events += strokes })
        sender.targetPID = { nil }
        sender.enqueueTap(copy)
        try await wait { events.contains { !$0.modifier && $0.down } }
        sender.releaseAll()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(events.filter { !$0.modifier && !$0.down }.count, 1)
        XCTAssertEqual(events.last?.flags, 0)
        XCTAssertNil(sender.heldID)
    }

    func testModifierGestureRetainsHIDAndImmediatePress() throws {
        let option = NamedShortcut(name: "Option", key: .init(code: 58, modifiers: 1 << 19, label: "Option"))
        var events: [ShortcutStroke] = []
        let sender = ShortcutSender(permissionCheck: { true }, eventSink: { strokes, tap in
            XCTAssertEqual(tap, .cghidEventTap)
            events += strokes
        })
        sender.targetPID = { nil }
        try sender.press(option)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].down)
        sender.release(option)
        XCTAssertEqual(events.count, 2)
        XCTAssertFalse(events[1].down)
        XCTAssertEqual(events[1].flags, 0)
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Shortcut delivery did not complete")
    }
}
