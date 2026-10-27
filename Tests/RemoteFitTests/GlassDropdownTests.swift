import AppKit
import XCTest
@testable import RemoteFit

@MainActor
final class GlassDropdownTests: XCTestCase {
    func testMenuDoesNotStealFocusAndSelectionReachesOwner() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 300, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: CGRect(x: 20, y: 80, width: 200, height: 30))
        window.contentView?.addSubview(anchor)
        window.makeKeyAndOrderFront(nil)
        let controller = GlassDropdownController<String>()
        controller.anchor = anchor
        defer { controller.close(); window.close() }
        var selected: String?
        controller.toggle(label: "规格", items: [.init(id: "phone", title: "手机")], selected: nil) { selected = $0 }
        let menu = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(controller.state.isOpen)
        XCTAssertFalse(menu.canBecomeKey, "The menu must not dismiss itself by taking focus from its parent")
        menu.makeKey()
        XCTAssertTrue(controller.state.isOpen)
        try await Task.sleep(for: .milliseconds(100))
        menu.contentView?.layoutSubtreeIfNeeded()
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = try XCTUnwrap(NSEvent.mouseEvent(with: type,
                                                       location: CGPoint(x: menu.frame.width / 2, y: menu.frame.height / 2),
                                                       modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: menu.windowNumber, context: nil,
                                                       eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            NSApp.sendEvent(click)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(selected, "phone", "Clicking a row must reach the settings callback")
        XCTAssertFalse(controller.state.isOpen)

        selected = nil
        controller.toggle(label: "规格", items: [.init(id: "phone", title: "手机")], selected: nil) { selected = $0 }
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                  timestamp: 0, windowNumber: window.windowNumber,
                                                  context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                                  isARepeat: false, keyCode: 36))
        NSApp.sendEvent(enter)
        XCTAssertEqual(selected, "phone")
        XCTAssertFalse(controller.state.isOpen)
    }
}
