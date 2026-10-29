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

    // MARK: - 反转滚动方向

    private struct Deltas: Equatable {
        var line1, line2, point1, point2: Int64
        var fixed1, fixed2: Double
        init(_ e: CGEvent) {
            line1 = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            line2 = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            point1 = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            point2 = e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            fixed1 = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            fixed2 = e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        var negated: Deltas {
            var d = self
            (d.line1, d.line2, d.point1, d.point2) = (-line1, -line2, -point1, -point2)
            (d.fixed1, d.fixed2) = (-fixed1, -fixed2)
            return d
        }
    }
    private func reversing() -> UUNativeScroll {
        let engine = make()
        engine.setPercent(100)
        engine.setReversed(true)
        return engine
    }
    private func lineEvent(remote: Bool = true) -> CGEvent {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0)!
        e.setIntegerValueField(.eventSourceUnixProcessID, value: remote ? 900 : 901)
        return e
    }

    func testReversalNegatesLinePointAndFixedDeltasOnBothAxes() {
        let engine = reversing(); defer { engine.stop() }
        for e in [event(y: 100, x: -50), lineEvent()] {
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
            let before = Deltas(e)
            XCTAssertNotEqual(before.line1, 0); XCTAssertNotEqual(before.line2, 0)
            XCTAssertNotEqual(before.point1, 0); XCTAssertNotEqual(before.fixed2, 0)
            XCTAssertTrue(apply(engine, e))
            XCTAssertEqual(Deltas(e), before.negated)
            XCTAssertEqual(e.getIntegerValueField(.scrollWheelEventScrollPhase), 2)
            XCTAssertEqual(e.getIntegerValueField(.eventSourceUnixProcessID), 900)
            // Fed back by another handler: never flipped twice.
            XCTAssertTrue(apply(engine, e))
            XCTAssertEqual(Deltas(e), before.negated)
        }
        XCTAssertEqual(engine.snapshot.adjusted, 2)
    }

    func testReversalNeverTouchesLocalOrTouchGeneratedEvents() {
        let engine = reversing(); defer { engine.stop() }
        engine.setPercent(10)
        let touch = event(); touch.setIntegerValueField(.eventSourceUserData, value: UUTouchScroll.marker)
        let local = event(remote: false)
        let localModified = event(remote: false); localModified.flags = .maskCommand
        for e in [local, localModified, lineEvent(remote: false), touch] {
            let before = Deltas(e)
            XCTAssertTrue(apply(engine, e))
            XCTAssertEqual(Deltas(e), before)
        }
        XCTAssertEqual(engine.snapshot.adjusted, 0)
    }

    func testReversalCombinesWithSpeedAndKeepsModifiedMagnitudes() {
        let engine = reversing(); defer { engine.stop() }
        engine.setPercent(10)
        let scaled = event(y: 200, x: -100)
        XCTAssertTrue(apply(engine, scaled))
        XCTAssertEqual(scaled.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -20)
        XCTAssertEqual(scaled.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 10)
        // Fixed-point follows Quartz's canonical pixel→line conversion; only the sign is asserted.
        XCTAssertLessThan(scaled.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0)
        XCTAssertGreaterThan(scaled.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 0)
        XCTAssertLessThan(scaled.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        let zoom = event(y: 100, x: -50); zoom.flags = .maskCommand
        let before = Deltas(zoom)
        XCTAssertTrue(apply(engine, zoom))
        XCTAssertEqual(Deltas(zoom), before.negated)
    }

    func testReversalOffLeavesRemoteEventsAlone() {
        let engine = make(); defer { engine.stop() }
        engine.setPercent(100)
        let e = event()
        let before = Deltas(e)
        XCTAssertTrue(apply(engine, e))
        XCTAssertEqual(Deltas(e), before)
        engine.setReversed(true)
        engine.setReversed(false)
        let again = event()
        XCTAssertTrue(apply(engine, again))
        XCTAssertEqual(Deltas(again), before)
        XCTAssertEqual(engine.snapshot.adjusted, 0)
    }
}
