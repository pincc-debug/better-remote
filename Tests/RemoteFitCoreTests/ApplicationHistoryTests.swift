import XCTest
@testable import RemoteFitCore

final class ApplicationHistoryTests: XCTestCase {
    func testPreviousTogglesBetweenTwoApps() {
        var h = ApplicationHistory()
        h.activate(1); h.activate(2)
        XCTAssertEqual(h.previous(excluding: 2), 1)
        h.activate(1)
        XCTAssertEqual(h.previous(excluding: 1), 2)
        h.activate(2); h.activate(2)
        XCTAssertEqual(h.recent, [2, 1])
    }
    func testTerminatedAppsCannotBeSelectedAndEmptyHistoryDoesNotGuess() {
        var h = ApplicationHistory()
        XCTAssertNil(h.previous(excluding: 1))
        h.activate(1); h.activate(2); h.activate(3)
        h.retain([1, 3])
        XCTAssertEqual(h.previous(excluding: 3), 1)
        h.retain([3])
        XCTAssertNil(h.previous(excluding: 3))
    }
    func testOurSettingsWindowDoesNotEraseLastExternalApp() {
        var h = ApplicationHistory()
        h.activate(5); h.activate(6)
        XCTAssertEqual(h.previous(excluding: nil), 6)
    }
    func testFloatingPreferenceMigrationAndRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(old.toolbarWhenConnected)
        XCTAssertFalse(old.toolbarWhenDisconnected)
        var current = old; current.toolbarWhenDisconnected = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(current))
        XCTAssertTrue(decoded.toolbarWhenDisconnected)
    }
}
