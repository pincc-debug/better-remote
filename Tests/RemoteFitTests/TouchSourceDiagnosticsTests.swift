import AppKit
import XCTest
@testable import RemoteFit

final class TouchSourceDiagnosticsTests: XCTestCase {
    func testSourceLineCarriesInjectedEventFields() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 12, y: 34), mouseButton: .left))
        event.setIntegerValueField(.mouseEventSubtype, value: 1)
        event.setIntegerValueField(.mouseEventClickState, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: 77)
        event.setDoubleValueField(.mouseEventPressure, value: 1)
        let line = UUTouchScroll.sourceFields(of: event, label: "down", app: "uu", elapsedMs: 0)
        for part in ["ev=down", "app=uu", "ms=0", "subtype=1", "pressure=1.000", "click=2", "userData=77", "state=", "tabX=", "proxPtr=", "x=12", "y=34"] {
            XCTAssertTrue(line.contains(part), "\(part) missing in \(line)")
        }
        XCTAssertFalse(line.contains("\n"))
    }

    func testDiagnosticsDoNotChangeTouchDecisions() {
        let tested = UUTouchScroll(sourceOverride: { _ in true }, mouseSink: { _, _ in }, pointerLocation: { CGPoint(x: 100, y: 100) })
        tested.isOwnWindow = { _ in false }
        defer { tested.stop() }
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 100, y: 100), mouseButton: .left)!
        // A remote press is still held back for the scroll/drag decision, exactly as before.
        XCTAssertTrue(EventTapThread.shared.sync { tested.handle(.leftMouseDown, down) })
    }
}
