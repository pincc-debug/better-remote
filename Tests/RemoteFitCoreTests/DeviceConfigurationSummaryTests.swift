import XCTest
@testable import RemoteFitCore

final class DeviceConfigurationSummaryTests: XCTestCase {
    private func preferences() -> Preferences {
        var p = Preferences()
        p.customPresets = [CustomPreset(id: "p15", name: "iPhone 15", width: 1179, height: 2556)]
        p.remember(.init(id: "uu:window:Phone", name: "Phone"))
        p.setConfiguration(p.configuration(for: nil), for: "uu:window:Phone")
        return p
    }

    func testDefaultCardAndUnchangedDevice() {
        let p = preferences()
        XCTAssertEqual(DeviceConfigurationSummary.text(for: nil, in: p), "新设备沿用这套")
        XCTAssertEqual(DeviceConfigurationSummary.text(for: "uu:window:Phone", in: p), "使用默认")
    }

    func testListsOnlyDifferencesInOrder() {
        var p = preferences()
        var c = p.configuration(for: "uu:window:Phone")
        c.uuTouchScrollEnabled.toggle()
        c.selectResolution("p15")
        p.setConfiguration(c, for: "uu:window:Phone")
        let scroll = c.uuTouchScrollEnabled ? "开" : "关"
        XCTAssertEqual(DeviceConfigurationSummary.text(for: "uu:window:Phone", in: p), "分辨率：iPhone 15 · 单指滚动：\(scroll)")
    }

    func testOtherFields() {
        let base = Preferences().configuration(for: nil)
        var c = base
        c.uuScrollSpeedPercent = base.uuScrollSpeedPercent == 50 ? 75 : 50
        c.remoteScrollReversed.toggle()
        c.autoFillWindowsOnRemote.toggle()
        c.connectionDockMode = base.connectionDockMode == .keep ? .autoHide : .keep
        c.selectResolution("gone")
        let items = DeviceConfigurationSummary.items(c, comparedTo: base) { _ in nil }
        XCTAssertEqual(items.first, "分辨率：自定义")
        XCTAssertTrue(items.contains("滚动速度：\(c.uuScrollSpeedPercent)%"))
        XCTAssertTrue(items.contains { $0.hasPrefix("反转滚动：") })
        XCTAssertTrue(items.contains { $0.hasPrefix("窗口铺满：") })
        XCTAssertTrue(items.contains("程序坞：\(c.connectionDockMode.title)"))
    }

    func testToolbarSideOnlyWhenShown() {
        var base = Preferences().configuration(for: nil)
        base.toolbarWhenConnected = .toolbar
        base.toolbarSide = .right
        var c = base
        c.toolbarSide = .left
        XCTAssertEqual(DeviceConfigurationSummary.items(c, comparedTo: base) { _ in nil }, ["工具条：左侧"])
        c.toolbarWhenConnected = .ball
        XCTAssertEqual(DeviceConfigurationSummary.items(c, comparedTo: base) { _ in nil }, ["工具条：悬浮球"])
    }

    func testClearingResolutionShowsNoSwitch() {
        var base = Preferences().configuration(for: nil)
        base.selectResolution("p15")
        var c = base
        c.selectResolution(nil)
        XCTAssertEqual(DeviceConfigurationSummary.items(c, comparedTo: base) { _ in "iPhone 15" }, ["分辨率：不切换"])
    }
    func testRustDeskSummaryOmitsUnsupportedScrollButKeepsCommonSettings() {
        var p = preferences()
        let id = "rustdesk:id:123456789"
        p.remember(.init(id: id, name: "123456789"))
        var c = p.configuration(for: nil)
        c.uuTouchScrollEnabled.toggle()
        c.uuScrollSpeedPercent = 50
        c.remoteScrollReversed.toggle()
        p.setConfiguration(c, for: id)
        XCTAssertEqual(DeviceConfigurationSummary.text(for: id, in: p), "使用默认")
        c.selectResolution("p15")
        p.setConfiguration(c, for: id)
        XCTAssertEqual(DeviceConfigurationSummary.text(for: id, in: p), "分辨率：iPhone 15")
        XCTAssertEqual(p.configuration(for: id), c)
    }

    func testUUSummaryKeepsAllSupportedScrollSettings() {
        var p = preferences()
        let id = "uu:window:Phone"
        var c = p.configuration(for: id)
        c.uuTouchScrollEnabled.toggle()
        c.uuScrollSpeedPercent = 50
        c.remoteScrollReversed.toggle()
        p.setConfiguration(c, for: id)
        let summary = DeviceConfigurationSummary.text(for: id, in: p)
        XCTAssertTrue(summary.contains("单指滚动："))
        XCTAssertTrue(summary.contains("滚动速度：50%"))
        XCTAssertTrue(summary.contains("反转滚动："))
    }

    func testSoftwareScrollCapabilities() {
        XCTAssertTrue(RemoteSoftware.uu.supportsSingleFingerScroll)
        XCTAssertTrue(RemoteSoftware.uu.supportsScrollReversal)
        XCTAssertTrue(RemoteSoftware.uu.supportsScrollSpeed)
        XCTAssertFalse(RemoteSoftware.rustDesk.supportsSingleFingerScroll)
        XCTAssertFalse(RemoteSoftware.rustDesk.supportsScrollReversal)
        XCTAssertFalse(RemoteSoftware.rustDesk.supportsScrollSpeed)
        XCTAssertTrue(RemoteSoftware.toDesk.supportsSingleFingerScroll)
        XCTAssertFalse(RemoteSoftware.toDesk.supportsScrollReversal)
        XCTAssertFalse(RemoteSoftware.toDesk.supportsScrollSpeed)
        XCTAssertFalse(RemoteSoftware.anyDesk.supportsSingleFingerScroll)
        XCTAssertFalse(RemoteSoftware.anyDesk.supportsScrollReversal)
        XCTAssertFalse(RemoteSoftware.anyDesk.supportsScrollSpeed)
    }

    func testEffectiveSummaryShowsActualConfigInsteadOfUsesDefault() {
        var p = preferences()
        let id = "uu:window:Phone"
        var c = p.configuration(for: nil)
        c.selectResolution("p15")
        c.toolbarWhenConnected = .toolbar
        p.setConfiguration(c, for: nil)
        p.setConfiguration(c, for: id)
        XCTAssertEqual(DeviceConfigurationSummary.effectiveSummary(for: nil, in: p), "iPhone 15 · 显示工具条")
        XCTAssertEqual(DeviceConfigurationSummary.effectiveSummary(for: id, in: p), "iPhone 15 · 显示工具条")
        XCTAssertEqual(DeviceConfigurationSummary.users(of: "p15", in: p), ["默认配置", "Phone"])
    }
}
