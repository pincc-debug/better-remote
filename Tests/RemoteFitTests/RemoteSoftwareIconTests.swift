import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class RemoteSoftwareIconTests: XCTestCase {
    func testShippedIconsDrawAt16ptWithHighDensityRepresentations() {
        for name in ["uu", "rustdesk"] {
            let image = RemoteSoftwareIcon.image(named: name)
            let loaded = try? XCTUnwrap(image)
            XCTAssertEqual(loaded?.size, NSSize(width: 16, height: 16), name)
            let pixels = Set((loaded?.representations ?? []).map { "\($0.pixelsWide)x\($0.pixelsHigh)" })
            XCTAssertTrue(pixels.contains("32x32"), "\(name) missing @2x 32")
            XCTAssertTrue(pixels.contains("64x64"), "\(name) missing 64")
            XCTAssertTrue(pixels.contains("128x128"), "\(name) missing 128")
            XCTAssertEqual(loaded?.isTemplate, false)
        }
        XCTAssertEqual(RemoteSoftwareIcon.pointSize, 16)
        XCTAssertEqual(RemoteSoftwareIcon.borderWidth, 0.5)
        XCTAssertNotNil(RemoteSoftwareIcon.image(for: .uu))
        XCTAssertNotNil(RemoteSoftwareIcon.image(for: .rustDesk))
        XCTAssertNil(RemoteSoftwareIcon.image(for: .toDesk))
        XCTAssertNil(RemoteSoftwareIcon.image(for: .anyDesk))
    }
}
