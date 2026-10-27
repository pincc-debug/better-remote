import XCTest
@testable import RemoteFitCore
final class ShortcutPermissionStateTests: XCTestCase {
    func testAccessibilityStatusDoesNotDependOnPostingPreflight() {
        XCTAssertFalse(ShortcutPermissionState(accessibility: false, eventPosting: true).granted)
        XCTAssertTrue(ShortcutPermissionState(accessibility: true, eventPosting: false).granted)
        XCTAssertTrue(ShortcutPermissionState(accessibility: true, eventPosting: true).granted)
    }
    func testGrantedAndRevokedStatesStayAccurate() {
        XCTAssertEqual(ShortcutPermissionState(accessibility: true, eventPosting: false).title, "已授权")
        XCTAssertEqual(ShortcutPermissionState(accessibility: false, eventPosting: false).title, "未授权")
        XCTAssertEqual(ShortcutPermissionState(accessibility: true, eventPosting: true).title, "已授权")
    }
}
