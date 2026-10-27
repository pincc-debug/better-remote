import XCTest
@testable import RemoteFitCore

final class UUIdentifyHintTests: XCTestCase {
    private let phone = RemoteDevice(id: "uu:window:手机", name: "手机")

    func testPermissionMissingHint() {
        let hint = UUIdentifyHintBuilder.build(
            status: "permission_missing", device: nil, deviceHasPreset: false,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: true, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "需要辅助功能权限才能识别设备")
        XCTAssertEqual(hint?.actionTitle, "去开启")
        XCTAssertEqual(hint?.action, .openAccessibility)
    }

    func testAppMissingHintHasNoAction() {
        let hint = UUIdentifyHintBuilder.build(
            status: "app_missing", device: nil, deviceHasPreset: false,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: true, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "打开 UU 远程后才能识别设备")
        XCTAssertNil(hint?.actionTitle)
        XCTAssertNil(hint?.action)
    }

    func testUnrecognizedUsesDefaultCopyWhenDefaultOn() {
        let hint = UUIdentifyHintBuilder.build(
            status: "ax_unavailable", device: nil, deviceHasPreset: false,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: true, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "没认出这台设备，已用默认分辨率")
        XCTAssertEqual(hint?.actionTitle, "重试")
    }

    func testUnrecognizedHonestWhenDefaultOff() {
        let hint = UUIdentifyHintBuilder.build(
            status: "timeout", device: nil, deviceHasPreset: false,
            defaultResolutionEnabled: false, hasDefaultPreset: true,
            exhausted: true, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "没认出这台设备")
        XCTAssertEqual(hint?.action, .retry)
    }

    func testRecognizedNoPresetUsesDefaultCopy() {
        let hint = UUIdentifyHintBuilder.build(
            status: "read", device: phone, deviceHasPreset: false,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: false, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "已识别「手机」，还没设分辨率，先用默认")
        XCTAssertEqual(hint?.actionTitle, "设置")
        XCTAssertEqual(hint?.action, .openSettings)
    }

    func testRecognizedNoPresetHonestWhenDefaultOff() {
        let hint = UUIdentifyHintBuilder.build(
            status: "read", device: phone, deviceHasPreset: false,
            defaultResolutionEnabled: false, hasDefaultPreset: false,
            exhausted: false, deviceResolutionEnabled: true
        )
        XCTAssertEqual(hint?.message, "已识别「手机」，还没设分辨率")
    }

    func testSuccessWithPresetShowsNothing() {
        let hint = UUIdentifyHintBuilder.build(
            status: "read", device: phone, deviceHasPreset: true,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: false, deviceResolutionEnabled: true
        )
        XCTAssertNil(hint)
    }

    func testNotExhaustedFailureShowsNothing() {
        let hint = UUIdentifyHintBuilder.build(
            status: "ax_unavailable", device: nil, deviceHasPreset: false,
            defaultResolutionEnabled: true, hasDefaultPreset: true,
            exhausted: false, deviceResolutionEnabled: true
        )
        XCTAssertNil(hint)
    }
}
