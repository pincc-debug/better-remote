import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class ToolbarDensityTests: XCTestCase {
    private func content(density: DesktopToolbarLayout.Density, side: ToolbarSide = .right) -> ToolbarContent {
        let frame = CGRect(x: 0, y: 0, width: side.isHorizontal ? 720 : 72, height: side.isHorizontal ? 74 : 720)
        let grid = DesktopToolbarLayout.grid(in: frame, count: 10, side: side, windowControls: true)
        let view = ToolbarContent(frame: frame, grid: grid, side: side)
        view.grip.isHidden = true
        view.density = density
        let names = ["回车", "复制", "粘贴", "撤销", "全选", "切换应用", "显示桌面", "截图", "搜索", "锁屏"]
        let symbols = ["return", "doc.on.doc", "doc.on.clipboard", "arrow.uturn.backward", "selection.pin.in.out", "square.stack", "macwindow", "camera", "magnifyingglass", "lock"]
        for (name, symbol) in zip(names, symbols) {
            let button = ToolbarButton(symbol: symbol, name: name)
            view.buttons.append(button)
            view.document.addSubview(button)
        }
        view.layout()
        for button in view.buttons { button.layout() }
        return view
    }

    func testTightLayoutFitsAndKeepsCaptionsAndIconsInsideButtons() {
        let regular = content(density: .regular)
        let tight = content(density: .tight)
        XCTAssertGreaterThan(regular.maxOffset, 0)
        XCTAssertEqual(tight.maxOffset, 0)
        for button in tight.buttons {
            XCTAssertEqual(button.frame.height, 48)
            for subview in button.subviews { XCTAssertTrue(button.bounds.contains(subview.frame)) }
        }
        tight.setOffset(1000)
        XCTAssertEqual(tight.offset, 0)
        XCTAssertEqual(content(density: .tight, side: .top).buttons.first?.frame.height, 58)
    }

    func testRenderDensityComparison() throws {
        guard let path = ProcessInfo.processInfo.environment["BR_DENSITY_SHOTS"] else { return }
        _ = NSApplication.shared
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 760))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = root
        for (index, density) in DesktopToolbarLayout.Density.allCases.enumerated() {
            let view = content(density: density)
            view.frame.origin = CGPoint(x: 24 + index * 112, y: 12)
            root.addSubview(view)
            let title = NSTextField(labelWithString: ["58 pt", "52 pt", "48 pt"][index])
            title.frame = CGRect(x: 24 + index * 112, y: 735, width: 72, height: 18)
            title.alignment = .center
            root.addSubview(title)
        }
        root.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        window.close()
    }
}
