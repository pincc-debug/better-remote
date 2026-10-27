import XCTest
@testable import RemoteFitCore

final class ShowDesktopActionTests: XCTestCase {
    func testShowDesktopIsConfigurable() {
        XCTAssertEqual(FloatingAction.showDesktop.title, "清理桌面")
        XCTAssertEqual(FloatingAction.showDesktop.hint, "最小化所有窗口")
        XCTAssertTrue(FloatingAction.configurableActions.contains(.showDesktop))
    }

    func testExistingUsersGetShowDesktopAfterMinimizeOnce() throws {
        var old = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
        old.floatingActions = [.runningApplications, .fillWindow, .minimizeWindow]
        old.seededShowDesktopAction = false
        let migrated = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(migrated.floatingActions, [.runningApplications, .fillWindow, .minimizeWindow, .showDesktop])
        var off = migrated
        off.floatingActions.removeAll { $0 == .showDesktop }
        let again = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(again.floatingActions.contains(.showDesktop))
    }
}
