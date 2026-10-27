import XCTest
@testable import RemoteFitCore

final class ShortcutPresetCatalogTests: XCTestCase {
    func testBundledCatalogIncludesConfiguredOperations() throws {
        let catalog = try ShortcutPresetCatalog.bundled()
        let names = Set(catalog.presets.map(\.name))
        XCTAssertTrue(Set(["复制", "粘贴", "聚焦搜索", "回车", "调度中心", "左移桌面", "右移桌面"]).isSubset(of: names))
        // Window management lives in the built-in toolbar actions; 关闭窗口 (⌘W) is the one approved optional preset.
        XCTAssertTrue(names.isDisjoint(with: ["最小化", "切换全屏", "最大化"]))
        XCTAssertEqual(catalog.presets.first(where: { $0.name == "调度中心" })?.key,
                       ShortcutKey(code: 126, modifiers: 1 << 18, label: "↑"))
    }

    func testRejectsUnsupportedVersionDuplicateAndInvalidPresets() throws {
        let catalog = try ShortcutPresetCatalog.bundled()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        object["schemaVersion"] = 2
        XCTAssertThrowsError(try ShortcutPresetCatalog.decode(JSONSerialization.data(withJSONObject: object)))
        object["schemaVersion"] = 1
        let first = try XCTUnwrap(catalog.presets.first)
        object["presets"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([first, first]))
        XCTAssertThrowsError(try ShortcutPresetCatalog.decode(JSONSerialization.data(withJSONObject: object)))
        var invalid = first
        invalid.key.code = 200
        object["presets"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))
        XCTAssertThrowsError(try ShortcutPresetCatalog.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testOverrideLoadsEditsAndReportsMalformedJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("shortcut-presets.json")
        XCTAssertFalse(try ShortcutPresetCatalog.load(overrideURL: file).presets.isEmpty)
        try Data(#"{"schemaVersion":1,"updatedAt":"2026-10-09","presets":[]}"#.utf8).write(to: file)
        XCTAssertTrue(try ShortcutPresetCatalog.load(overrideURL: file).presets.isEmpty)
        try Data("invalid".utf8).write(to: file)
        XCTAssertThrowsError(try ShortcutPresetCatalog.load(overrideURL: file))
    }
}
