import XCTest
@testable import RemoteFitCore
final class NamedShortcutTests: XCTestCase {
    func testComboReleasesEveryModifierInReverseOrder() {
        let key = ShortcutKey(code: 8, modifiers: (1 << 20) | (1 << 17), label: "⇧⌘C")
        let plan = ShortcutEventPlan.strokes(for: key)
        XCTAssertEqual(plan.press.map(\.code), [55, 56, 8])
        XCTAssertEqual(plan.release.map(\.code), [8, 56, 55])
        XCTAssertTrue(plan.press.allSatisfy(\.down))
        XCTAssertFalse(plan.release.contains(where: \.down))
        XCTAssertEqual(plan.release.last?.flags, 0)
    }
    func testOptionAloneUsesFlagsChangedAndKeepsSide() {
        let key = ShortcutKey(code: 61, modifiers: 1 << 19, label: "⌥")
        let plan = ShortcutEventPlan.strokes(for: key)
        XCTAssertEqual(plan.press.count, 1)
        XCTAssertEqual(plan.press.first?.code, 61)
        XCTAssertEqual(plan.press.first?.flags, (1 << 19) | 0x40)
        XCTAssertEqual(plan.press.first?.modifier, true)
        XCTAssertEqual(plan.release.first?.flags, 0)
    }
    func testLeftAndRightOptionHaveDistinctDeviceFlags() {
        let left = ShortcutEventPlan.strokes(for: .init(code: 58, modifiers: 1 << 19, label: "Option 左"))
        let right = ShortcutEventPlan.strokes(for: .init(code: 61, modifiers: 1 << 19, label: "Option 右"))
        XCTAssertEqual(left.press.first?.flags, 0x80020)
        XCTAssertEqual(right.press.first?.flags, 0x80040)
        XCTAssertEqual(left.release.first?.flags, 0)
        XCTAssertEqual(right.release.first?.flags, 0)
    }
    func testOldShortcutGetsDefaultIconAndCustomIconRoundTrips() throws {
        let data = Data(#"{"id":"old","name":"语音","key":{"code":61,"modifiers":524288,"label":"Option 右"},"mode":"press"}"#.utf8)
        var item = try JSONDecoder().decode(NamedShortcut.self, from: data)
        XCTAssertEqual(item.icon, .keyboard)
        XCTAssertTrue(item.enabled)
        item.icon = .microphone
        let decoded = try JSONDecoder().decode(NamedShortcut.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.icon, .microphone)
    }
    func testInvalidShortcutProducesNoEvents() {
        XCTAssertTrue(ShortcutEventPlan.strokes(for: .init(code: 200, modifiers: 0, label: "x")).press.isEmpty)
        XCTAssertTrue(ShortcutEventPlan.strokes(for: .init(code: 8, modifiers: UInt64.max, label: "C")).press.isEmpty)
        XCTAssertFalse(NamedShortcut(name: " ", key: .init(code: 8, modifiers: 0, label: "C")).isValid)
    }
    func testClickCountAndHoldLastComposeStoredModes() throws {
        XCTAssertEqual(NamedShortcut.Mode.resolved(clicks: 1, holdsLast: false), .press)
        XCTAssertEqual(NamedShortcut.Mode.resolved(clicks: 1, holdsLast: true), .hold)
        XCTAssertEqual(NamedShortcut.Mode.resolved(clicks: 2, holdsLast: false), .doublePress)
        XCTAssertEqual(NamedShortcut.Mode.resolved(clicks: 2, holdsLast: true), .tapHold)
        let item = NamedShortcut(name: "语音", key: .init(code: 61, modifiers: 1 << 19, label: "⌥"), mode: .tapHold)
        let decoded = try JSONDecoder().decode(NamedShortcut.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.mode.clickCount, 2)
        XCTAssertTrue(decoded.mode.holdsLast)
    }

    func testCustomActionsCanReplaceAllBuiltinsAndRoundTrip() throws {
        var p = Preferences()
        p.floatingActions = []
        p.namedShortcuts = [.init(name: "语音输入", key: .init(code: 58, modifiers: 1 << 19, label: "⌥"), mode: .doublePress)]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
    func testUnknownAndDuplicateBuiltinActionsMigrateWithoutBreakingSettings() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"floatingActions":["future","settings","settings","maximizeWindow","maximizeWindow"]}"#.utf8))
        XCTAssertEqual(p.floatingActions, [.maximizeWindow])
    }

    func testDisabledCustomShortcutRetainsItsConfigurationAfterReload() throws {
        var preferences = Preferences()
        preferences.floatingActions = []
        preferences.namedShortcuts = [.init(name: "语音输入", key: .init(code: 58, modifiers: 1 << 19, label: "⌥"), icon: .microphone, enabled: false)]
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        XCTAssertFalse(decoded.namedShortcuts[0].enabled)
        XCTAssertTrue(decoded.namedShortcuts[0].isValid)
    }

    func testTurningOffEveryBuiltinDoesNotRestoreDefaultsAfterReload() throws {
        var preferences = Preferences()
        preferences.floatingActions = []
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(decoded.floatingActions.isEmpty)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.floatingActions, FloatingAction.defaults)
    }

    func testRecommendedPresetsAreValidAndUnique() {
        XCTAssertFalse(NamedShortcut.recommendedPresets.isEmpty)
        var names = Set<String>()
        for preset in NamedShortcut.recommendedPresets {
            XCTAssertTrue(preset.isValid, "Preset \(preset.name) should be valid")
            XCTAssertTrue(preset.key.isValid, "Key for \(preset.name) should be valid")
            XCTAssertTrue(names.insert(preset.name).inserted, "Duplicate preset name: \(preset.name)")
        }
    }
}

