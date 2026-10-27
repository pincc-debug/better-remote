import AppKit
import XCTest
@testable import RemoteFit

@MainActor
final class StatusMenuImageTests: XCTestCase {
    func testStatusMenuHidesEveryItemImage() throws {
        guard #available(macOS 27.0, *) else { throw XCTSkip("preferredImageVisibility needs macOS 27") }
        let menu = NSMenu()
        for title in ["显示工具条", "还原本机分辨率", "设置…", "检查更新…", "退出 Better Remote"] {
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        menu.insertItem(.separator(), at: 2)
        AppController.hideMenuItemImages(in: menu)
        for item in menu.items where !item.isSeparatorItem {
            XCTAssertEqual(item.preferredImageVisibility, .hidden, item.title)
        }
    }
}
