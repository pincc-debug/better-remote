import Foundation

public struct DeviceTemplateCatalog: Codable, Sendable {
    public struct Category: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let brands: [Brand]
    }
    public struct Brand: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let models: [Model]
    }
    public struct Model: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let aliases: [String]?
        public let source: String
        public let screens: [Screen]
    }
    public struct Screen: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let width: Int
        public let height: Int
    }
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let categoryID: String
        public let brandID: String
        public let brandName: String
        public let modelName: String
        public let screenName: String
        public let aliases: [String]
        public let width: Int
        public let height: Int
        public var title: String { screenName == "主屏" ? modelName : "\(modelName) · \(screenName)" }
        /// Catalog sizes are physical pixels. Phones, tablets, foldables and Macs are high-density screens, so the
        /// remote desktop uses half of them as logical points (rendered at 2x, pixel-for-pixel on the device).
        /// Other computers and monitors keep their size as-is. Tiny cover screens shrink only down to the 512 minimum.
        public var pixelRatio: Double {
            guard categoryID != "computer" || brandID == "apple" else { return 1 }
            return max(1, min(2, Double(min(width, height)) / 512))
        }
        public var logicalWidth: Int { Int((Double(width) / pixelRatio).rounded(.down)) }
        public var logicalHeight: Int { Int((Double(height) / pixelRatio).rounded(.down)) }
        public var preset: CustomPreset { .init(id: "template:catalog:\(id)", name: title, width: logicalWidth, height: logicalHeight) }
        public func matches(_ query: String) -> Bool {
            let term = Self.normalize(query)
            return term.isEmpty || Self.normalize(([brandName, modelName, screenName] + aliases).joined(separator: " ")).contains(term)
        }
        private static func normalize(_ string: String) -> String {
            string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
        }
    }

    public let schemaVersion: Int
    public let updatedAt: String
    public let categories: [Category]
    public var entries: [Entry] {
        categories.flatMap { category in
            category.brands.flatMap { brand in
                brand.models.flatMap { model in
                    model.screens.map { screen in
                        Entry(id: "\(category.id)/\(brand.id)/\(model.id)/\(screen.id)", categoryID: category.id,
                            brandID: brand.id, brandName: brand.name, modelName: model.name, screenName: screen.name,
                            aliases: model.aliases ?? [], width: screen.width, height: screen.height)
                    }
                }
            }
        }
    }

    public static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, !catalog.categories.isEmpty else {
            throw FitError.message("设备模板格式不支持。")
        }
        var ids = Set<String>()
        for entry in catalog.entries {
            guard ids.insert(entry.id).inserted else { throw FitError.message("设备模板编号重复。") }
            try entry.preset.validate()
        }
        return catalog
    }

    public static func bundled() throws -> Self {
        let resource = Bundle.main.url(forResource: "device-templates", withExtension: "json")
            ?? Bundle.module.url(forResource: "device-templates", withExtension: "json")
        guard let resource else { throw FitError.message("未找到设备模板。") }
        return try decode(Data(contentsOf: resource))
    }

    public static func load(overrideURL: URL? = nil) throws -> Self {
        if let overrideURL, FileManager.default.fileExists(atPath: overrideURL.path) {
            return try decode(Data(contentsOf: overrideURL))
        }
        return try bundled()
    }
}
