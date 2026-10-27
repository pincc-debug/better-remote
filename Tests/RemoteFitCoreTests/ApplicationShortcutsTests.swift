import XCTest
@testable import RemoteFitCore

final class ApplicationShortcutsTests: XCTestCase {
    let copy = NamedShortcut(name: "复制", key: .init(code: 8, modifiers: 1 << 20, label: "C"))

    func testLegacyPreferencesStartDisabledAndKeepGlobalShortcuts() throws {
        let original = Preferences()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "applicationShortcuts")
        json.removeValue(forKey: "applicationShortcutsEnabled")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.applicationShortcutsEnabled)
        XCTAssertTrue(decoded.applicationShortcuts.isEmpty)
        XCTAssertEqual(decoded.namedShortcuts, original.namedShortcuts)
    }

    func testConfigurationSurvivesDisabledSwitchAndMatchesBundleOnly() throws {
        var prefs = Preferences()
        prefs.namedShortcuts = [copy]
        prefs.applicationShortcuts = [.init(bundleID: "com.apple.finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app", shortcuts: [copy])]
        prefs = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(prefs.applicationShortcuts.first?.shortcuts, [copy])
        XCTAssertNil(prefs.applicationShortcuts(for: "com.apple.finder"))
        prefs.applicationShortcutsEnabled = true
        XCTAssertEqual(prefs.applicationShortcuts(for: "com.apple.finder")?.enabledShortcuts, [copy])
        XCTAssertNil(prefs.applicationShortcuts(for: "Finder"))
        XCTAssertNil(prefs.applicationShortcuts(for: nil))
        prefs.applicationShortcuts[0].shortcuts[0].enabled = false
        XCTAssertNil(prefs.applicationShortcuts(for: "com.apple.finder"))
        XCTAssertEqual(prefs.namedShortcuts, [copy])
    }

    func testApplicationEntryReservesOneFixedRowWithOrWithoutTrafficLights() {
        for windows in [false, true] {
            XCTAssertEqual(DesktopToolbarLayout.footerHeight(windowControls: windows, applicationShortcut: true)
                - DesktopToolbarLayout.footerHeight(windowControls: windows), DesktopToolbarLayout.footerStep)
        }
    }

    func testReorderingPersistsAndKeepsFlyoutOrderAndShortcutDetails() throws {
        let paste = NamedShortcut(name: "粘贴", key: .init(code: 9, modifiers: 1 << 20, label: "V"))
        var disabled = NamedShortcut(name: "停用", key: .init(code: 0, modifiers: 1 << 20, label: "A"))
        disabled.enabled = false
        var group = ApplicationShortcuts(bundleID: "test.app", name: "Test", path: "/Test.app", shortcuts: [copy, disabled, paste])
        XCTAssertTrue(group.moveShortcut(copy.id, to: paste.id))
        XCTAssertEqual(group.shortcuts, [disabled, paste, copy])
        group = try JSONDecoder().decode(ApplicationShortcuts.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(group.enabledShortcuts, [paste, copy])
        XCTAssertTrue(group.moveShortcut(copy.id, to: disabled.id))
        XCTAssertEqual(group.shortcuts, [copy, disabled, paste])
    }

    func testReorderingRejectsForeignOrMissingShortcuts() {
        var group = ApplicationShortcuts(bundleID: "test.app", name: "Test", path: "/Test.app", shortcuts: [copy])
        XCTAssertFalse(group.moveShortcut("another-app-shortcut", to: copy.id))
        XCTAssertFalse(group.moveShortcut(copy.id, to: "removed-shortcut"))
        XCTAssertFalse(group.moveShortcut(copy.id, to: copy.id))
        XCTAssertEqual(group.shortcuts, [copy])
    }
}
