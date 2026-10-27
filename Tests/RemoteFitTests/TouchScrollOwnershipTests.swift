import AppKit
import XCTest
@testable import RemoteFit

private final class MouseEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(CGEventType, CGPoint)] = []
    func append(_ type: CGEventType, _ point: CGPoint) { lock.lock(); defer { lock.unlock() }; values.append((type, point)) }
    var events: [(CGEventType, CGPoint)] { lock.lock(); defer { lock.unlock() }; return values }
}

final class TouchScrollOwnershipTests: XCTestCase {
    private func event(_ type: CGEventType, remote: Bool, point: CGPoint = CGPoint(x: 100, y: 100)) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        event.setIntegerValueField(.eventSourceUserData, value: remote ? 900 : 0)
        return event
    }
    private func make(_ log: MouseEventLog) -> UUTouchScroll {
        let input = UUTouchScroll(sourceOverride: { $0.getIntegerValueField(.eventSourceUserData) == 900 },
                                  mouseSink: { log.append($0, $1) }, pointerLocation: { CGPoint(x: 100, y: 100) })
        input.isOwnWindow = { _ in false }
        return input
    }
    func testLocalMotionCancelsDelayedRemotePressWithoutChangingMotion() async throws {
        let log = MouseEventLog()
        let tested = make(log)
        defer { tested.stop() }
        let down = event(.leftMouseDown, remote: true)
        XCTAssertTrue(EventTapThread.shared.sync { tested.handle(.leftMouseDown, down) })
        let motion = event(.mouseMoved, remote: false, point: CGPoint(x: 400, y: 300))
        XCTAssertFalse(EventTapThread.shared.sync { tested.handle(.mouseMoved, motion) })
        XCTAssertEqual(motion.location, CGPoint(x: 400, y: 300))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(log.events.isEmpty)
    }
    func testLocalTakeoverReleasesInjectedHoldAtIncomingPointer() async throws {
        let log = MouseEventLog()
        let input = make(log)
        defer { input.stop() }
        let down = event(.leftMouseDown, remote: true)
        _ = EventTapThread.shared.sync { input.handle(.leftMouseDown, down) }
        try await waitForPress(log)
        let point = CGPoint(x: 400, y: 300)
        let motion = event(.mouseMoved, remote: false, point: point)
        XCTAssertFalse(EventTapThread.shared.sync { input.handle(.mouseMoved, motion) })
        XCTAssertEqual(log.events.map { $0.0 }, [.leftMouseDown, .leftMouseUp])
        XCTAssertEqual(log.events.last?.1, point)
        input.stop()
        XCTAssertEqual(log.events.count, 2)
    }
    func testStoppingReleasesInjectedHoldExactlyOnce() async throws {
        let log = MouseEventLog()
        let input = make(log)
        let down = event(.leftMouseDown, remote: true)
        _ = EventTapThread.shared.sync { input.handle(.leftMouseDown, down) }
        try await waitForPress(log)
        input.stop(); input.stop()
        XCTAssertEqual(log.events.map { $0.0 }, [.leftMouseDown, .leftMouseUp])
    }
    private func waitForPress(_ log: MouseEventLog) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while log.events.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(log.events.first?.0, .leftMouseDown)
    }
}
