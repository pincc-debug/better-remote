import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class ToolbarMotionTests: XCTestCase {
    private func fixture() throws -> (FloatingSwitcher, NSWindow) {
        _ = NSApplication.shared
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let switcher = FloatingSwitcher()
        switcher.reduceMotion = { false }
        var preferences = Preferences()
        preferences.theme = .dark
        switcher.configure(preferences: preferences)
        switcher.setEnabled(true)
        let panel = try XCTUnwrap(NSApp.windows.first { !existing.contains($0.windowNumber) && $0.title == "Better Remote 快捷操作" })
        return (switcher, panel)
    }
    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("Toolbar transition did not settle"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func capture(_ window: NSWindow, name: String) throws {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/toolbar-transition-20261013/frames")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }

    func testExpansionHasIntermediateFrameAndSettlesAtExpandedSize() async throws {
        let (switcher, panel) = try fixture()
        defer { switcher.setEnabled(false); panel.close() }
        let start = panel.frame
        try capture(panel, name: "start")
        switcher.toggleList()
        XCTAssertTrue(switcher.isTransitioning)
        try await until { panel.frame.height > start.height + 40 && switcher.isTransitioning }
        let middle = panel.frame
        try capture(panel, name: "middle")
        try await until { !switcher.isTransitioning }
        XCTAssertTrue(switcher.isExpanded)
        XCTAssertGreaterThan(panel.frame.height, middle.height)
        XCTAssertGreaterThan(middle.height, start.height)
        try capture(panel, name: "end")
    }

    func testQuickReverseAndDisableCannotLeaveOldAnimationRunning() async throws {
        let (switcher, panel) = try fixture()
        defer { switcher.setEnabled(false); panel.close() }
        let collapsed = panel.frame
        switcher.toggleList()
        try await until { panel.frame.height > collapsed.height + 40 }
        switcher.toggleList()
        try await until { !switcher.isTransitioning }
        XCTAssertFalse(switcher.isExpanded)
        XCTAssertTrue(WindowLayout.approximatelyEqual(panel.frame, collapsed))
        switcher.toggleList()
        switcher.setEnabled(false)
        XCTAssertFalse(switcher.isTransitioning)
        XCTAssertFalse(panel.isVisible)
    }

    func testReduceMotionSkipsTransitionAndContentAnimations() throws {
        let (switcher, panel) = try fixture()
        defer { switcher.setEnabled(false); panel.close() }
        switcher.reduceMotion = { true }
        switcher.toggleList()
        XCTAssertTrue(switcher.isExpanded)
        XCTAssertFalse(switcher.isTransitioning)
    }
}
