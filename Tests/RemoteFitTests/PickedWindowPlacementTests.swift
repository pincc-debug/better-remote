import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
private final class SizeLimitedWindow: NSWindow {
    var enforcedWidth: CGFloat = 0
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        var frame = frameRect
        frame.size.width = max(frame.width, enforcedWidth)
        super.setFrame(frame, display: flag, animate: animate)
    }
}

@MainActor
final class PickedWindowPlacementTests: XCTestCase {
    private func window(minimumWidth: CGFloat = 0) -> SizeLimitedWindow {
        let window = SizeLimitedWindow(contentRect: CGRect(x: 80, y: 80, width: 900, height: 500),
                                       styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.enforcedWidth = minimumWidth
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        return window
    }
    private func item(_ window: NSWindow) -> ScreenWindow {
        .init(number: window.windowNumber, pid: getpid(), bounds: window.frame, layer: 0)
    }

    func testTwoLimitedWindowsArePlacedAndReportSizeLimitInsteadOfZero() async throws {
        _ = NSApplication.shared
        let area = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let width = area.width / 2 + 36
        let left = window(minimumWidth: width), right = window(minimumWidth: width)
        let oldArea = WindowControlPerformer.layoutArea
        defer { left.close(); right.close(); WindowControlPerformer.layoutArea = oldArea; WindowControlPerformer.beginPicked() }
        WindowControlPerformer.layoutArea = { _ in area }
        WindowControlPerformer.beginPicked()
        WindowControlPerformer.placePicked(.halves, window: item(left), slot: 0)
        WindowControlPerformer.placePicked(.halves, window: item(right), slot: 1)
        let message = await WindowControlPerformer.endPicked(.halves)
        XCTAssertEqual(message, "窗口尺寸受限")
        XCTAssertEqual(left.frame.minX, area.minX, accuracy: 2)
        XCTAssertEqual(right.frame.maxX, area.maxX, accuracy: 2)
        XCTAssertEqual(left.frame.width, width, accuracy: 2)
        XCTAssertEqual(right.frame.width, width, accuracy: 2)
    }

    func testARealFailureKeepsTheSuccessfulWindowCount() async throws {
        _ = NSApplication.shared
        let area = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let right = window()
        let oldArea = WindowControlPerformer.layoutArea
        defer { right.close(); WindowControlPerformer.layoutArea = oldArea; WindowControlPerformer.beginPicked() }
        WindowControlPerformer.layoutArea = { _ in area }
        WindowControlPerformer.beginPicked()
        let missing = ScreenWindow(number: Int.max, pid: getpid(), bounds: area, layer: 0)
        WindowControlPerformer.placePicked(.halves, window: missing, slot: 0)
        WindowControlPerformer.placePicked(.halves, window: item(right), slot: 1)
        let message = await WindowControlPerformer.endPicked(.halves)
        XCTAssertEqual(message, "已排列 1 个窗口，1 个未完成")
        XCTAssertEqual(right.frame.maxX, area.maxX, accuracy: 2)
    }

    func testAnOldCompletionCannotResetNewSessionResults() async throws {
        _ = NSApplication.shared
        let area = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let right = window()
        let oldArea = WindowControlPerformer.layoutArea
        defer { right.close(); WindowControlPerformer.layoutArea = oldArea; WindowControlPerformer.beginPicked() }
        WindowControlPerformer.layoutArea = { _ in area }
        let oldSession = WindowControlPerformer.beginPicked()
        let newSession = WindowControlPerformer.beginPicked()
        WindowControlPerformer.placePicked(.halves, window: .init(number: Int.max, pid: getpid(), bounds: area, layer: 0), slot: 0)
        WindowControlPerformer.placePicked(.halves, window: item(right), slot: 1)
        let stale = await WindowControlPerformer.endPicked(.halves, generation: oldSession)
        XCTAssertNil(stale)
        let message = await WindowControlPerformer.endPicked(.halves, generation: newSession)
        XCTAssertEqual(message, "已排列 1 个窗口，1 个未完成")
    }
}
