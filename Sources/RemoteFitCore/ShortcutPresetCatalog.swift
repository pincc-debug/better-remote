import Foundation

public struct ShortcutPresetCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let presets: [NamedShortcut]

    public static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw FitError.message("快捷操作预设格式不支持。")
        }
        var ids = Set<String>()
        var names = Set<String>()
        for preset in catalog.presets {
            guard preset.isValid else { throw FitError.message("快捷操作预设无效。") }
            guard !preset.id.isEmpty, ids.insert(preset.id).inserted,
                  names.insert(preset.name).inserted else {
                throw FitError.message("快捷操作预设重复。")
            }
        }
        return catalog
    }

    public static func bundled() throws -> Self {
        let resource = Bundle.main.url(forResource: "shortcut-presets", withExtension: "json")
            ?? Bundle.module.url(forResource: "shortcut-presets", withExtension: "json")
        guard let resource else { throw FitError.message("未找到快捷操作预设。") }
        return try decode(Data(contentsOf: resource))
    }

    public static func load(overrideURL: URL? = nil) throws -> Self {
        if let overrideURL, FileManager.default.fileExists(atPath: overrideURL.path) {
            return try decode(Data(contentsOf: overrideURL))
        }
        return try bundled()
    }
}
