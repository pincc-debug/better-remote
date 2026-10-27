import XCTest
@testable import RemoteFitCore

final class MinimizeActionTests: XCTestCase {
    func testMinimizeIsDefaultRightAfterFill() {
        XCTAssertEqual(FloatingAction.minimizeWindow.title, "最小化")
        XCTAssertNotNil(ShortcutIcon(rawValue: FloatingAction.minimizeWindow.symbol))
        XCTAssertTrue(FloatingAction.configurableActions.contains(.minimizeWindow))
        let ids = Preferences().enabledOperations.map(\.id)
        XCTAssertEqual(ids.firstIndex(of: "builtin:minimizeWindow"), ids.firstIndex(of: "builtin:fillWindow").map { $0 + 1 })
    }

    func testExistingUsersGetMinimizeAfterFillOnce() throws {
        let legacy = Data(#"{"floatingActions":["runningApplications","fillWindow"],"operationOrder":["shortcut:a","builtin:fillWindow","builtin:runningApplications"]}"#.utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
        XCTAssertEqual(migrated.floatingActions, [.runningApplications, .fillWindow, .minimizeWindow, .showDesktop])
        XCTAssertEqual(migrated.operationOrder, ["shortcut:a", "builtin:fillWindow", "builtin:minimizeWindow", "builtin:showDesktop", "builtin:runningApplications"])
        // Once migrated, a user who turns it off keeps it off.
        var off = migrated
        off.floatingActions.removeAll { $0 == .minimizeWindow }
        let again = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(again.floatingActions.contains(.minimizeWindow))
    }

    func testShortcutPresetsHaveNoScreenshot() throws {
        let catalog = try ShortcutPresetCatalog.bundled()
        XCTAssertFalse(catalog.presets.contains { $0.id == "preset:screenshot" || $0.name.contains("截图") })
    }
}

final class CloseWindowPresetTests: XCTestCase {
    func testCloseWindowPresetSendsCommandWAndIsNotDefault() throws {
        let preset = try XCTUnwrap(ShortcutPresetCatalog.bundled().presets.first { $0.id == "preset:close-window" })
        XCTAssertEqual(preset.name, "关闭窗口")
        XCTAssertEqual(preset.key.code, 13)
        XCTAssertEqual(preset.key.modifiers, 1 << 20)
        XCTAssertEqual(preset.icon, .windowClose)
        XCTAssertFalse(preset.icon.rawValue.contains("fill"))
        XCTAssertTrue(Preferences().namedShortcuts.isEmpty)
        XCTAssertFalse(Preferences().enabledOperations.map(\.id).contains { $0.contains("close-window") })
    }
}
