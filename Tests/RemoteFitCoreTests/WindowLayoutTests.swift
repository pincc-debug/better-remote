import XCTest
import CoreGraphics
@testable import RemoteFitCore

final class WindowLayoutTests: XCTestCase {
    func testExpansionMovesOverlapsAwayFromEachEdgeWithoutResizing() throws {
        let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let cases: [(ToolbarSide, CGRect, CGRect, CGPoint)] = [
            (.right, CGRect(x: 1120, y: 25, width: 80, height: 800), CGRect(x: 900, y: 200, width: 280, height: 400), CGPoint(x: 840, y: 200)),
            (.left, CGRect(x: 0, y: 25, width: 80, height: 800), CGRect(x: 20, y: 200, width: 280, height: 400), CGPoint(x: 80, y: 200)),
            (.top, CGRect(x: 0, y: 25, width: 1200, height: 80), CGRect(x: 200, y: 40, width: 500, height: 400), CGPoint(x: 200, y: 105)),
            (.bottom, CGRect(x: 0, y: 745, width: 1200, height: 80), CGRect(x: 200, y: 400, width: 500, height: 400), CGPoint(x: 200, y: 345))
        ]
        for (side, toolbar, original, origin) in cases {
            let target = try XCTUnwrap(WindowLayout.avoidingToolbar(original, toolbar: toolbar, screen: screen, side: side))
            XCTAssertEqual(target.size, original.size)
            XCTAssertEqual(target.origin, origin)
        }
    }

    func testExpansionLeavesNonoverlappingAndEdgeTouchingWindowsAlone() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let toolbar = CGRect(x: 1120, y: 0, width: 80, height: 800)
        for window in [CGRect(x: 100, y: 100, width: 600, height: 500), CGRect(x: 520, y: 100, width: 600, height: 500)] {
            XCTAssertNil(WindowLayout.avoidingToolbar(window, toolbar: toolbar, screen: screen, side: .right))
        }
    }

    func testOversizedOverlapsTrimOnlyTheBlockedAxis() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        XCTAssertEqual(WindowLayout.avoidingToolbar(screen, toolbar: CGRect(x: 1120, y: 0, width: 80, height: 800), screen: screen, side: .right), CGRect(x: 0, y: 0, width: 1120, height: 800))
        XCTAssertEqual(WindowLayout.avoidingToolbar(screen, toolbar: CGRect(x: 0, y: 720, width: 1200, height: 80), screen: screen, side: .bottom), CGRect(x: 0, y: 0, width: 1200, height: 720))
        XCTAssertEqual(WindowLayout.avoidingToolbar(screen, toolbar: CGRect(x: 0, y: 0, width: 80, height: 800), screen: screen, side: .left), CGRect(x: 80, y: 0, width: 1120, height: 800))
        XCTAssertEqual(WindowLayout.avoidingToolbar(screen, toolbar: CGRect(x: 0, y: 0, width: 1200, height: 80), screen: screen, side: .top), CGRect(x: 0, y: 80, width: 1200, height: 720))
    }

    func testChromeMaximizedWidthTrimsAndThenFillsBackOnCollapse() throws {
        let screen = CGRect(x: 0, y: 30, width: 1728, height: 1050)
        let toolbar = CGRect(x: 1648, y: 30, width: 72, height: 1050)
        let avoided = try XCTUnwrap(WindowLayout.avoidingToolbar(screen, toolbar: toolbar, screen: screen, side: .right))
        XCTAssertEqual(avoided, CGRect(x: 0, y: 30, width: 1648, height: 1050))
        XCTAssertEqual(WindowLayout.fillingCollapsedToolbar(avoided, toolbar: toolbar, screen: screen, side: .right), screen)
    }

    func testExpansionRespectsNegativeDisplayCoordinates() throws {
        let screen = CGRect(x: -1200, y: -800, width: 1200, height: 800)
        let window = CGRect(x: -400, y: -600, width: 360, height: 450)
        let moved = try XCTUnwrap(WindowLayout.avoidingToolbar(window, toolbar: CGRect(x: -80, y: -800, width: 80, height: 800), screen: screen, side: .right))
        XCTAssertEqual(moved, CGRect(x: -440, y: -600, width: 360, height: 450))
    }

    func testWorkspaceKeepsWindowOutOfRightHandReservedArea() {
        let area = CGRect(x: 0, y: 30, width: 1130, height: 690)
        let overlapping = CGRect(x: 800, y: 80, width: 600, height: 400)
        let fitted = WindowLayout.frame(overlapping, in: area, placement: .moveToScreen)
        XCTAssertTrue(area.contains(fitted))
        XCTAssertEqual(fitted.size, overlapping.size)
        XCTAssertEqual(WindowLayout.frame(CGRect(x: 20, y: 40, width: 1500, height: 900), in: area, placement: .moveToScreen), area)
    }

    func testLegacyWorkspaceSwitchAndActionAreRemovedWithoutChangingOtherPreferences() throws {
        for enabled in [true, false] {
            let data = Data("{\"leftWorkspaceEnabled\":\(enabled),\"floatingSwitcherEnabled\":true,\"toolbarSide\":\"bottom\",\"floatingActions\":[\"leftWorkspace\",\"resolution\",\"runningApplications\"],\"operationOrder\":[\"builtin:leftWorkspace\",\"builtin:resolution\",\"builtin:runningApplications\"]}".utf8)
            let preferences = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertTrue(preferences.toolbarWhenConnected)
            XCTAssertEqual(preferences.toolbarSide, .bottom)
            XCTAssertEqual(preferences.floatingActions, [.runningApplications])
            XCTAssertEqual(preferences.operationOrder, ["builtin:runningApplications"])
            let encoded = try JSONEncoder().encode(preferences)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertNil(object["leftWorkspaceEnabled"])
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: encoded), preferences)
        }
    }
    func testTargetDisplayFollowsWindowInsteadOfToolbar() {
        let left = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        let right = CGRect(x: 0, y: 25, width: 1280, height: 695)
        let window = CGRect(x: -1700, y: 100, width: 900, height: 600)
        XCTAssertEqual(WindowLayout.screen(containing: window, screens: [left, right], fallback: right), left)
        XCTAssertEqual(WindowLayout.screen(containing: CGRect(x: -100, y: 100, width: 800, height: 500), screens: [left, right], fallback: left), right)
    }
    func testMaximizeRespectsMenuBarAndDockInsetsOnNegativeOriginDisplay() {
        let visible = CGRect(x: -1920, y: 25, width: 1920, height: 1010)
        let current = CGRect(x: 50, y: 70, width: 600, height: 400)
        XCTAssertEqual(WindowLayout.frame(current, in: visible, placement: .maximize), visible)
    }

    func testCenterShrinksWideWindowForPortraitScreenWithoutStretchingHeight() {
        let visible = CGRect(x: 0, y: 25, width: 630, height: 1375)
        let current = CGRect(x: 2200, y: 50, width: 1600, height: 900)
        XCTAssertEqual(WindowLayout.frame(current, in: visible, placement: .center),
                       CGRect(x: 0, y: 262.5, width: 630, height: 900))
    }

    func testMoveRecoversWindowFromOtherDisplayAndPreservesItsSize() {
        let visible = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let current = CGRect(x: -1800, y: -500, width: 600, height: 400)
        XCTAssertEqual(WindowLayout.frame(current, in: visible, placement: .moveToScreen),
                       CGRect(x: 300, y: 225, width: 600, height: 400))
    }

    func testPartiallyOffscreenWindowIsClampedWithMinimalMovement() {
        let visible = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let current = CGRect(x: 1100, y: 750, width: 600, height: 400)
        XCTAssertEqual(WindowLayout.frame(current, in: visible, placement: .moveToScreen),
                       CGRect(x: 600, y: 425, width: 600, height: 400))
    }

    func testOversizedWindowFitsBothDimensionsAndAlreadyVisibleWindowStaysPut() {
        let visible = CGRect(x: -1000, y: -900, width: 800, height: 600)
        let oversized = CGRect(x: -500, y: -600, width: 1600, height: 1200)
        XCTAssertEqual(WindowLayout.frame(oversized, in: visible, placement: .moveToScreen), visible)
        let small = CGRect(x: -800, y: -700, width: 400, height: 300)
        XCTAssertEqual(WindowLayout.frame(small, in: visible, placement: .moveToScreen), small)
    }

    func testMaximizeRestoreUsesOriginalScreenIfItStillExists() {
        let original = CGRect(x: -1700, y: 80, width: 600, height: 400)
        let left = CGRect(x: -1920, y: 25, width: 1920, height: 1010)
        let main = CGRect(x: 0, y: 25, width: 1200, height: 800)
        XCTAssertEqual(WindowLayout.restoredFrame(original, screens: [left, main], fallback: main), original)
    }

    func testMaximizeRestoreAfterDisplayDisconnectRecoversWindowToRemainingScreen() {
        let original = CGRect(x: -1700, y: 80, width: 600, height: 400)
        let remaining = CGRect(x: 0, y: 25, width: 1200, height: 800)
        XCTAssertEqual(WindowLayout.restoredFrame(original, screens: [remaining], fallback: remaining),
                       CGRect(x: 300, y: 225, width: 600, height: 400))
    }

    func testWindowActionsPersistWithoutAutomaticallyEnablingThemForExistingUsers() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"floatingActions":["resolution"]}"#.utf8))
        XCTAssertEqual(legacy.floatingActions, [])
        var preferences = legacy
        preferences.floatingActions = [.maximizeWindow, .centerWindow]
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }

    @MainActor
    func testDelayedResizeIsReadAgainInsteadOfImmediatelyReportingFailure() async throws {
        let target = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let original = CGRect(x: 200, y: 100, width: 600, height: 400)
        var reads = 0
        let actual = try await WindowLayout.waitForFrame(target: target) {
            reads += 1
            return reads < 3 ? original : target
        }
        XCTAssertEqual(actual, target)
        XCTAssertEqual(reads, 3)
    }

    func testSizeRoundingAcceptsSmallInsetButNeverOversizedOrUnchangedSmallWindows() {
        let target = CGRect(x: 0, y: 25, width: 1200, height: 800)
        let rounded = CGRect(x: 0, y: 25, width: 1192, height: 785)
        XCTAssertTrue(WindowLayout.reached(rounded, target: target, allowsSizeRounding: true))
        XCTAssertFalse(WindowLayout.reached(rounded, target: target, allowsSizeRounding: false))
        XCTAssertFalse(WindowLayout.reached(CGRect(x: 0, y: 25, width: 1208, height: 800), target: target, allowsSizeRounding: true))
        XCTAssertFalse(WindowLayout.reached(CGRect(x: 0, y: 25, width: 600, height: 400), target: target, allowsSizeRounding: true))
    }

    @MainActor
    func testUnchangedWindowStillReportsAnActualFailureAfterWaiting() async {
        let target = CGRect(x: 0, y: 25, width: 1200, height: 800)
        do {
            _ = try await WindowLayout.waitForFrame(target: target) { CGRect(x: 20, y: 70, width: 600, height: 400) }
            XCTFail("An unchanged small window must not count as maximized")
        } catch {
            XCTAssertEqual(error.localizedDescription, "窗口未完成调整，请重试")
        }
    }

    func testRemovedButtonsAreDroppedFromPreviouslySavedPreferences() throws {
        let saved = Data(#"{"floatingActions":["maximizeWindow","undoWindowLayout","moveWindowToScreen","previousApplication"]}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(preferences.floatingActions, [.maximizeWindow])
    }
    @MainActor
    func testNativeZoomAcceptsAppChosenSizeAndWaitsForStableAnimation() async throws {
        let initial = CGRect(x: 100, y: 100, width: 600, height: 400)
        let intermediate = CGRect(x: 50, y: 60, width: 850, height: 600)
        let native = CGRect(x: 20, y: 33, width: 1100, height: 750)
        var reads = 0
        let actual = try await WindowLayout.waitForNativeZoom(from: initial) {
            reads += 1
            if reads == 1 { return initial }
            return reads == 2 ? intermediate : native
        }
        XCTAssertEqual(actual, native)
        XCTAssertEqual(reads, 5)
    }

    @MainActor
    func testNativeUnzoomAcceptsRestoredSizeWithoutCustomSavedBounds() async throws {
        let maximized = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let restored = CGRect(x: 90, y: 120, width: 880, height: 640)
        let actual = try await WindowLayout.waitForNativeZoom(from: maximized) { restored }
        XCTAssertEqual(actual, restored)
    }

}
