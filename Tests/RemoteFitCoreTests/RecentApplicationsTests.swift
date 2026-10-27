import XCTest
@testable import RemoteFitCore

final class RecentApplicationsTests: XCTestCase {
    func testReuseMovesApplicationToFrontWithoutDuplicates() {
        var recent = RecentApplications()
        recent.record("browser")
        recent.record("editor")
        recent.record("browser")
        XCTAssertEqual(recent.identifiers, ["browser", "editor"])
    }

    func testStoredHistoryKeepsOrderAndSkipsUninstalledAppsBeforeLimiting() throws {
        let data = try JSONEncoder().encode(["removed", "editor", "browser", "editor", ""])
        var recent = RecentApplications(try JSONDecoder().decode([String].self, from: data))
        XCTAssertEqual(recent.available(in: ["editor", "browser"], limit: 1), ["editor"])
        recent.record("browser")
        let reloaded = RecentApplications(try JSONDecoder().decode([String].self, from: JSONEncoder().encode(recent.identifiers)))
        XCTAssertEqual(reloaded.available(in: ["editor", "browser"]), ["browser", "editor"])
    }

    func testHistoryIsBoundedAndEmptyHistoryDoesNotInventRecency() {
        var recent = RecentApplications()
        XCTAssertEqual(recent.available(in: ["browser"]), [])
        for index in 0..<100 { recent.record("app-\(index)") }
        XCTAssertEqual(recent.identifiers.count, RecentApplications.limit)
        XCTAssertEqual(recent.identifiers.first, "app-99")
        XCTAssertFalse(recent.identifiers.contains("app-0"))
    }
}
