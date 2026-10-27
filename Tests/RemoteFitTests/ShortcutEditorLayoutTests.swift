import AppKit
import ObjectiveC
import SwiftUI
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class ShortcutEditorLayoutTests: XCTestCase {
    private func snapshot(_ view: NSView, name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["BR_SHORTCUT_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }

    private func settle(_ view: NSView, in window: NSWindow) {
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            window.setContentSize(view.fittingSize)
        }
    }

    func testChangingIconDoesNotShrinkEditor() throws {
        try checkPicker(limit: CGSize(width: 1168, height: 968), name: "desktop")
    }

    func testChangingIconOnSmallScreenKeepsFooterInsideLimit() throws {
        try checkPicker(limit: CGSize(width: 398, height: 520), name: "phone")
    }

    private func checkPicker(limit: CGSize, name: String) throws {
        _ = NSApplication.shared
        let previousArea = DialogLimit.settingsArea
        DialogLimit.settingsArea = CGRect(x: 0, y: 0, width: limit.width + 32, height: limit.height + 32)
        defer { DialogLimit.settingsArea = previousArea }
        let shortcut = NamedShortcut(name: "空间右", key: ShortcutKey(code: 124, modifiers: (1 << 20) | (1 << 19), label: "⌥⌘→"))
        let view = NSHostingView(rootView: ShortcutEditor(shortcut: shortcut, onSave: { _ in true }, onCancel: {}, onDelete: { true }))
        let window = NSWindow(contentRect: CGRect(x: -40000, y: -40000, width: 460, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        // Model a focused sheet without activating the test app or stealing user focus.
        let method = try XCTUnwrap(class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.keyWindow)))
        let original = method_getImplementation(method)
        let keyWindow: @convention(block) (AnyObject) -> NSWindow? = { _ in window }
        let replacement = imp_implementationWithBlock(keyWindow)
        method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        defer { window.close() }
        settle(view, in: window)
        let initialHeight = view.frame.height
        try snapshot(view, name: "\(name)-collapsed")

        func togglePicker() throws {
            // The icon row stays at the same distance from the top as the sheet grows.
            let point = CGPoint(x: view.frame.width - 42, y: view.frame.height - 312)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.sendEvent(event)
            }
            settle(view, in: window)
        }

        for _ in 0..<3 {
            try togglePicker()
            try snapshot(view, name: "\(name)-expanded")
            XCTAssertGreaterThan(view.frame.height, initialHeight + 100, "Opening the picker must grow the sheet")
            XCTAssertLessThanOrEqual(view.frame.height, limit.height)
            XCTAssertLessThanOrEqual(view.frame.width, limit.width)
            try togglePicker()
            XCTAssertEqual(view.frame.height, initialHeight, accuracy: 1, "Closing the picker must restore the original height")
        }
    }
}
