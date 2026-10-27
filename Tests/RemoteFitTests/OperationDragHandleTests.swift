import AppKit
import XCTest
@testable import RemoteFit

@MainActor
final class OperationDragHandleTests: XCTestCase {
    func testDragFrameKeepsGripAtItsOriginalLocationForEveryCardWidth() {
        let view = OperationDragHandleView(frame: NSRect(x: 0, y: 0, width: 20, height: 40))
        for width: CGFloat in [200, 290, 400] {
            view.cardSize = CGSize(width: width, height: 60)
            XCTAssertEqual(view.cardDraggingFrame.origin, CGPoint(x: -10, y: -10))
            XCTAssertEqual(view.cardDraggingFrame.size, view.cardSize)
            let pointerInCard = CGPoint(x: view.bounds.midX - view.cardDraggingFrame.minX,
                                        y: view.bounds.midY - view.cardDraggingFrame.minY)
            XCTAssertEqual(pointerInCard, CGPoint(x: 20, y: 30))
        }
    }

    func testPillSurfaceKeepsTheWholePillUnderThePointerAndPreservesClicks() throws {
        let view = OperationDragHandleView(frame: NSRect(x: 0, y: 0, width: 160, height: 36))
        view.coversCard = true
        XCTAssertEqual(view.cardDraggingFrame, view.bounds)
        var clicks = 0
        view.onTap = { clicks += 1 }
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        }
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 80, y: 18)))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 80, y: 18)))
        XCTAssertEqual(clicks, 1)
        view.mouseDown(with: try event(.leftMouseDown, at: CGPoint(x: 80, y: 18)))
        view.mouseUp(with: try event(.leftMouseUp, at: CGPoint(x: 180, y: 18)))
        XCTAssertEqual(clicks, 1, "Releasing outside the pill must not open the editor")
    }
}
