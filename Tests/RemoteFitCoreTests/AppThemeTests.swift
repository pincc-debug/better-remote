import XCTest
@testable import RemoteFitCore

final class AppThemeTests: XCTestCase {
    func testNewInstallDefaultsToDark() {
        XCTAssertEqual(Preferences().theme, .dark)
    }

    func testLegacyAndUnknownThemeFollowSystem() throws {
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).theme, .system)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(#"{"theme":"future"}"#.utf8)).theme, .system)
    }

    func testThemeRoundTripsWithoutChangingShortcutConfiguration() throws {
        var preferences = Preferences()
        preferences.namedShortcuts = [NamedShortcut(name: "复制", key: .init(code: 8, modifiers: 1 << 20, label: "⌘C"))]
        for theme in AppTheme.allCases {
            preferences.theme = theme
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(decoded, preferences)
        }
    }
}
