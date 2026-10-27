import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class WindowSnapIntegrationTests: XCTestCase {
    func testFillUsesTargetDisplayAndReservedToolbarOnEveryEdge() async throws {
        _ = NSApplication.shared
        let previous = WindowControlPerformer.layoutArea
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { WindowControlPerformer.layoutArea = previous; window.close() }
        for screen in NSScreen.screens {
            for side in ToolbarSide.allCases {
                let toolbar = DesktopToolbarLayout.toolbar(in: screen.visibleFrame, centerY: screen.visibleFrame.midY,
                                                          expanded: true, count: 3, side: side)
                let expected = DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen.visibleFrame, side: side)
                var selectedScreen: NSScreen?
                WindowControlPerformer.layoutArea = { target in
                    selectedScreen = target
                    return target == screen ? expected : target.visibleFrame
                }
                window.setFrame(CGRect(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.midY - 150,
                                       width: 400, height: 300), display: true)
                window.makeKeyAndOrderFront(nil)
                window.makeMain()
                try await Task.sleep(for: .milliseconds(40))
                do { try await WindowControlPerformer.snapOwn(.fill, window: window) }
                catch { XCTFail(error.localizedDescription); return }
                XCTAssertEqual(selectedScreen, screen)
                XCTAssertTrue(WindowLayout.approximatelyEqual(window.frame, expected), "actual=\(window.frame), expected=\(expected)")
                XCTAssertFalse(window.frame.intersects(toolbar))
            }
        }
    }
}
