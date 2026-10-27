import XCTest
@testable import RemoteFitCore

final class DeviceTemplateCoverageTests: XCTestCase {
    func testHuaweiAndHonorCoverPhonesTabletsAndFoldables() throws {
        let entries = try DeviceTemplateCatalog.bundled().entries
        for category in ["phone", "tablet", "foldable"] {
            XCTAssertTrue(entries.contains { $0.categoryID == category && $0.brandID == "huawei" }, category)
            XCTAssertTrue(entries.contains { $0.categoryID == category && $0.brandID == "honor" }, category)
        }
        XCTAssertGreaterThanOrEqual(entries.filter { $0.brandID == "huawei" }.count, 19)
        let mate = try XCTUnwrap(entries.first { $0.modelName == "华为 Mate 80 / 80 Pro" })
        XCTAssertEqual(mate.preset.dimensions(.standard), Dimensions(640, 1416))
        let x7 = try XCTUnwrap(entries.first { $0.modelName == "华为 Mate X7" && $0.screenName == "内屏" })
        XCTAssertEqual(x7.preset.dimensions(.standard), Dimensions(1105, 1208))
        XCTAssertTrue(mate.matches("mate80"))
    }
    func testEveryModelNamesItsBrandAndHasASource() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "device-templates", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for category in root["categories"] as? [[String: Any]] ?? [] {
            for brand in category["brands"] as? [[String: Any]] ?? [] {
                for model in brand["models"] as? [[String: Any]] ?? [] {
                    XCTAssertEqual(model["brand"] as? String, brand["name"] as? String, "\(model["id"] ?? "")")
                    XCTAssertFalse((model["source"] as? String ?? "").isEmpty)
                }
            }
        }
    }
}

final class DeviceTemplateOrderTests: XCTestCase {
    func testNewestModelsComeFirstWithinBrand() throws {
        let names = try DeviceTemplateCatalog.bundled().entries.filter { $0.categoryID == "phone" }.map(\.modelName)
        func index(_ n: String) throws -> Int { try XCTUnwrap(names.firstIndex(of: n), n) }
        XCTAssertLessThan(try index("iPhone 18 Pro Max"), try index("iPhone 18 Pro"))
        XCTAssertLessThan(try index("iPhone 18 Pro"), try index("iPhone 17e / 16e"))
        XCTAssertLessThan(try index("iPhone 17"), try index("iPhone 17e / 16e"))
        XCTAssertLessThan(try index("华为 Mate 90 Pro Max"), try index("华为 Mate 90"))
        XCTAssertLessThan(try index("华为 Mate 90"), try index("华为 Mate 80 / 80 Pro"))
    }
}
