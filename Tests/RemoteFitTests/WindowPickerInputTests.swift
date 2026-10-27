import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class WindowPickerInputTests: XCTestCase {
    func testRealWindowIsRecordedOnPressAndPlacedAfterReleaseWithoutOverlay() async throws {
        _ = NSApplication.shared
        let area = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let window = NSWindow(contentRect: CGRect(x: area.midX - 150, y: area.midY - 100, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(150))
        defer { window.close() }
        let picker = WindowPicker(permissionCheck: { true })
        defer { picker.end() }
        var placements: [(Int, Int)] = []
        let finished = expectation(description: "Selection completes")
        let windowsBefore = Set(NSApp.windows.map(\.windowNumber))
        XCTAssertTrue(picker.begin(.halves, prepicked: ScreenWindow(number: -1, pid: 0, bounds: .zero, layer: 0), place: { item, slot in
            placements.append((item.number, slot))
        }, finished: { finished.fulfill() }))
        XCTAssertEqual(Set(NSApp.windows.map(\.windowNumber)), windowsBefore)
        let live = try XCTUnwrap(WindowControlPerformer.screenWindows().first { $0.number == window.windowNumber })
        let point = CGPoint(x: live.bounds.midX, y: live.bounds.midY)
        let down = try XCTUnwrap(NSEvent(cgEvent: CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)!))
        let up = try XCTUnwrap(NSEvent(cgEvent: CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)!))
        picker.observe(up) // The release of the layout button is not a selection.
        XCTAssertTrue(placements.isEmpty)
        picker.observe(down)
        XCTAssertTrue(placements.isEmpty)
        picker.observe(up)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements.first?.0, window.windowNumber)
        XCTAssertEqual(placements.first?.1, 1)
        XCTAssertFalse(picker.isActive)
    }
}
