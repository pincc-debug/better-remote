import AppKit
import XCTest
@testable import RemoteFit

final class UUNativeScrollTests: XCTestCase {
    private func make() -> UUNativeScroll {
        let engine = UUNativeScroll(sourceOverride: { $0.getIntegerValueField(.eventSourceUnixProcessID) == 900 })
        engine.setPercent(10)
        return engine
    }
    private func event(y: Int32 = 100, x: Int32 = -50, remote: Bool = true) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
        event.setIntegerValueField(.eventSourceUnixProcessID, value: remote ? 900 : 901)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: 123)
        event.location = CGPoint(x: 150, y: 250)
        event.timestamp = 123456789
        return event
    }
    private func apply(_ engine: UUNativeScroll, _ event: CGEvent, type: CGEventType = .scrollWheel) -> Bool {
        EventTapThread.shared.sync { engine.handle(type, event) }
    }

    func testScalesBothAxesInPlaceAndPreservesRoutingAndGestureMetadata() {
        let engine = make(); defer { engine.stop() }
        engine.setPercent(5)
        let e = event(y: 200, x: -100)
        e.flags = .maskShift
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        XCTAssertTrue(apply(engine, e))
        XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 10)
        XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -5)
        XCTAssertEqual(e.getIntegerValueField(.eventSourceUnixProcessID), 900)
        XCTAssertEqual(e.getIntegerValueField(.eventTargetUnixProcessID), 123)
        XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventScrollPhase), 2)
        XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventMomentumPhase), 1)
        XCTAssertEqual(e.timestamp, 123456789)
        XCTAssertEqual(e.location, CGPoint(x: 150, y: 250))
        XCTAssertEqual(e.flags, .maskShift)
        // Even if another handler feeds the same event back, it is never scaled twice.
        XCTAssertTrue(apply(engine, e))
        XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 10)
    }

    func testLocalModifiedAndTouchGeneratedEventsPassThrough() {
        let engine = make(); defer { engine.stop() }
        let local = event(remote: false)
        let touch = event(); touch.setIntegerValueField(.eventSourceUserData, value: UUTouchScroll.marker)
        var inputs = [local, touch]
        for flag: CGEventFlags in [.maskControl, .maskCommand, .maskAlternate] {
            let e = event(); e.flags = flag; inputs.append(e)
        }
        for e in inputs {
            XCTAssertTrue(apply(engine, e))
            XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 100)
        }
        XCTAssertEqual(engine.snapshot.adjusted, 0)
    }

    func testZeroMotionIsSuppressedButGestureBoundariesSurvive() {
        let engine = make(); defer { engine.stop() }
        engine.setPercent(1)
        XCTAssertFalse(apply(engine, event(y: 1, x: 0)))
        for phase in [1, 4, 8] {
            let boundary = event(y: 0, x: 0)
            boundary.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            XCTAssertTrue(apply(engine, boundary))
            XCTAssertEqual(boundary.getIntegerValueField(.scrollWheelEventScrollPhase), Int64(phase))
        }
    }

    func testPercentageChangeAndBypassClearFractionalResidue() {
        let engine = make(); defer { engine.stop() }
        XCTAssertFalse(apply(engine, event(y: 9, x: 0)))
        _ = apply(engine, event(remote: false))
        XCTAssertFalse(apply(engine, event(y: 2, x: 0)))
        engine.setPercent(100)
        let full = event()
        XCTAssertTrue(apply(engine, full))
        XCTAssertEqual(full.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 100)
        engine.setPercent(1)
        XCTAssertFalse(apply(engine, event(y: 1, x: 0)))
        _ = apply(engine, event(), type: .tapDisabledByTimeout)
        XCTAssertFalse(apply(engine, event(y: 1, x: 0)))
    }
}
