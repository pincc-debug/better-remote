import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class SettingsWindowLayoutTests: XCTestCase {
    func testDesktopKeepsPreferredSizeAndPosition() {
        let visible = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        XCTAssertEqual(SettingsWindowLayout.frameSize(in: visible), SettingsWindowLayout.preferredSize)
        let frame = CGRect(x: 100, y: 200, width: 900, height: 720)
        XCTAssertEqual(SettingsWindowLayout.clampedFrame(frame, in: visible), frame)
    }

    func testPhonePortraitShrinksToScreenWithMargins() {
        let visible = CGRect(x: 0, y: 0, width: 430, height: 900)
        let frame = SettingsWindowLayout.clampedFrame(CGRect(x: 300, y: 50, width: 900, height: 720), in: visible)
        XCTAssertEqual(frame.width, 430 - 2 * SettingsWindowLayout.screenMargin)
        XCTAssertEqual(frame.height, 720)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertTrue(SettingsWindowLayout.isNarrow(contentWidth: frame.width))
    }

    func testShortScreenShrinksHeight() {
        let visible = CGRect(x: 0, y: 25, width: 1400, height: 605)
        let frame = SettingsWindowLayout.clampedFrame(CGRect(x: 0, y: 0, width: 900, height: 720), in: visible)
        XCTAssertEqual(frame.width, 900)
        XCTAssertEqual(frame.height, 605 - 2 * SettingsWindowLayout.screenMargin)
        XCTAssertTrue(visible.contains(frame))
    }

    func testMinimumWidthAndTinyScreens() {
        let narrow = CGRect(x: 0, y: 0, width: 370, height: 800)
        XCTAssertEqual(SettingsWindowLayout.frameSize(in: narrow).width, 360)
        let tiny = CGRect(x: 0, y: 0, width: 320, height: 300)
        let size = SettingsWindowLayout.frameSize(in: tiny)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 300)
        XCTAssertTrue(tiny.contains(SettingsWindowLayout.clampedFrame(CGRect(x: 500, y: 500, width: 900, height: 720), in: tiny)))
    }

    func testChromeIsAddedToFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        XCTAssertEqual(SettingsWindowLayout.frameSize(in: visible, chrome: CGSize(width: 0, height: 28)), CGSize(width: 900, height: 748))
    }

    func testOffscreenFrameMovesInside() {
        let visible = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let frame = SettingsWindowLayout.clampedFrame(CGRect(x: 1600, y: 900, width: 900, height: 720), in: visible)
        XCTAssertEqual(frame.size, CGSize(width: 900, height: 720))
        XCTAssertTrue(visible.contains(frame))
    }

    func testNarrowThreshold() {
        XCTAssertTrue(SettingsWindowLayout.isNarrow(contentWidth: 559))
        XCTAssertFalse(SettingsWindowLayout.isNarrow(contentWidth: 560))
        XCTAssertFalse(SettingsWindowLayout.isNarrow(contentWidth: 900))
    }

    func testDialogLimitKeepsDesignedSizeOnDesktopAndShrinksOnPhone() {
        let desktop = SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 33, width: 1728, height: 1084))
        for (w, h) in [(460.0, nil), (420.0, nil), (440.0, 480.0), (580.0, 510.0)] as [(CGFloat, CGFloat?)] {
            let size = SettingsWindowLayout.dialogSize(width: w, height: h, limit: desktop)
            XCTAssertEqual(size.width, w)
            XCTAssertEqual(size.height, h)
        }
        let phone = SettingsWindowLayout.dialogLimit(in: CGRect(x: 0, y: 0, width: 430, height: 500))
        XCTAssertEqual(phone, CGSize(width: 398, height: 468))
        let templates = SettingsWindowLayout.dialogSize(width: 580, height: 510, limit: phone)
        XCTAssertEqual(templates.width, 398)
        XCTAssertEqual(templates.height, 468)
        XCTAssertNil(SettingsWindowLayout.dialogSize(width: 420, height: nil, limit: phone).height)
    }

    /// 设置 uses the 铺满 area: DesktopToolbarLayout.workspace(presence:toolbar:in:side:).
    func testExpandedToolbarAreaMakesPhoneWindowNarrow() {
        // 手机竖屏（保留操作栏）603 × 1156 with the toolbar expanded on the right (live test, 0.8.147).
        let visible = CGRect(x: 0, y: 0, width: 603, height: 1126)
        let toolbar = CGRect(x: 531, y: 30, width: 72, height: 1126)
        let area = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: toolbar, in: visible, side: .right)
        XCTAssertEqual(area, CGRect(x: 0, y: 0, width: 531, height: 1126))
        let frame = SettingsWindowLayout.clampedFrame(CGRect(x: 12, y: 233, width: 579, height: 720), in: area)
        XCTAssertFalse(frame.intersects(toolbar))
        XCTAssertEqual(frame.maxX, toolbar.minX - SettingsWindowLayout.screenMargin)
        XCTAssertTrue(SettingsWindowLayout.isNarrow(contentWidth: frame.width))
        XCTAssertEqual(SettingsWindowLayout.dialogLimit(in: area).width, 531 - 2 * SettingsWindowLayout.dialogMargin)
        // Collapsed or hidden toolbar: nothing is subtracted.
        for presence in [DesktopToolbarLayout.Presence.collapsed, .hidden] {
            XCTAssertEqual(DesktopToolbarLayout.workspace(presence: presence, toolbar: toolbar, in: visible, side: .right), visible)
        }
        // Left dock: the window sits right of the toolbar.
        let left = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: CGRect(x: 0, y: 30, width: 72, height: 1126), in: visible, side: .left)
        XCTAssertGreaterThanOrEqual(SettingsWindowLayout.clampedFrame(CGRect(x: 12, y: 233, width: 579, height: 720), in: left).minX, 72)
        // Desktop: a centred 900 pt window is far from the right toolbar and keeps its frame.
        let desktopArea = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: CGRect(x: 1656, y: 0, width: 72, height: 1084),
                                                         in: CGRect(x: 0, y: 0, width: 1728, height: 1084), side: .right)
        let centred = CGRect(x: 414, y: 182, width: 900, height: 720)
        XCTAssertEqual(SettingsWindowLayout.clampedFrame(centred, in: desktopArea), centred)
    }

    func testToolbarGapOnlyWhenToolbarSubtracted() {
        let visible = CGRect(x: 0, y: 0, width: 1252, height: 1126)
        XCTAssertEqual(SettingsWindowLayout.spacedFromToolbar(visible, visible: visible, side: .right), visible)
        // 折叠屏（内）1252 wide, toolbar expanded on the right from x = 1180 (live test): 900 pt window, 8 pt clear of it.
        let area = DesktopToolbarLayout.workspace(presence: .expanded, toolbar: CGRect(x: 1180, y: 30, width: 72, height: 1126), in: visible, side: .right)
        let spaced = SettingsWindowLayout.spacedFromToolbar(area, visible: visible, side: .right)
        XCTAssertEqual(spaced.maxX, 1180 - SettingsWindowLayout.toolbarGap)
        let frame = SettingsWindowLayout.clampedFrame(CGRect(x: 280, y: 254, width: 900, height: 720), in: spaced)
        XCTAssertEqual(frame.size, CGSize(width: 900, height: 720))
        XCTAssertLessThanOrEqual(frame.maxX, 1172)
        XCTAssertEqual(SettingsWindowLayout.spacedFromToolbar(CGRect(x: 72, y: 0, width: 1180, height: 1126), visible: visible, side: .left).minX, 80)
    }
}
