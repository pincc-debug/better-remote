import XCTest
@testable import RemoteFitCore

final class RemoteDeviceKindTests: XCTestCase {
    func testComputerNames() {
        for name in ["Hilda的MacBook", "Hilda的MacBook Pro", "张三的Mac", "iMac", "Mac mini", "MAC-STUDIO", "Windows-PC", "DESKTOP-7K2Q9AB",
                     "LAPTOP-ABC", "我的电脑", "公司笔记本", "HUAWEI MateBook X", "ThinkPad X1", "Surface Laptop", "office pc", "Computer"] {
            XCTAssertEqual(RemoteDeviceKind.classify(name), .computer, name)
        }
    }

    func testPhoneAndTabletNames() {
        for name in ["vivo X Fold6", "vivoV2545A", "iPhone 13", "李的iPad", "HUAWEI Mate 60", "MatePad Pro", "小米14", "Redmi K70",
                     "OPPO Find N3", "Galaxy Z Flip5", "Pixel 8", "荣耀Magic6", "手机", "平板", "Phone"] {
            XCTAssertEqual(RemoteDeviceKind.classify(name), .mobile, name)
        }
    }

    func testUnknownNamesAndWordBoundaries() {
        for name in ["", "客厅", "Machine01", "XPCOM", "Hilda", "新设备"] {
            XCTAssertEqual(RemoteDeviceKind.classify(name), .unknown, name)
        }
    }

    func testNewComputerDeviceStartsWithOneFingerScrollOff() {
        var preferences = Preferences()
        preferences.uuTouchScrollEnabled = true
        preferences.remember(.init(id: "uu:window:Hilda的MacBook", name: "Hilda的MacBook"))
        let device = preferences.remoteDevices[0]
        XCTAssertEqual(device.isNew, true)
        XCTAssertFalse(device.configuration?.uuTouchScrollEnabled ?? true)
        // Everything except one-finger scroll is still copied from the defaults.
        var expected = preferences.configuration(for: nil)
        expected.uuTouchScrollEnabled = false
        XCTAssertEqual(device.configuration, expected)
        // The defaults themselves are untouched.
        XCTAssertTrue(preferences.uuTouchScrollEnabled)
    }

    func testNewPhoneAndUnknownDevicesCopyDefaults() {
        for enabled in [true, false] {
            var preferences = Preferences()
            preferences.uuTouchScrollEnabled = enabled
            preferences.remember(.init(id: "uu:window:vivo X Fold6", name: "vivo X Fold6"))
            preferences.remember(.init(id: "uu:window:客厅", name: "客厅"))
            XCTAssertEqual(preferences.remoteDevices[0].configuration, preferences.configuration(for: nil))
            XCTAssertEqual(preferences.remoteDevices[1].configuration, preferences.configuration(for: nil))
        }
    }

    func testExistingDeviceConfigurationIsNotChanged() {
        var preferences = Preferences()
        preferences.uuTouchScrollEnabled = true
        let id = "uu:window:Hilda的MacBook"
        preferences.remoteDevices = [.init(id: id, name: "Hilda的MacBook", configuration: DeviceConfiguration(preferences: preferences))]
        preferences.remember(.init(id: id, name: "Hilda的MacBook"))
        XCTAssertTrue(preferences.configuration(for: id).uuTouchScrollEnabled)
        XCTAssertNil(preferences.remoteDevices[0].isNew)
    }

    func testComputerDefaultStillOffWhenDefaultsAlreadyOff() {
        var preferences = Preferences()
        preferences.uuTouchScrollEnabled = false
        preferences.remember(.init(id: "uu:window:iMac", name: "iMac"))
        XCTAssertFalse(preferences.configuration(for: "uu:window:iMac").uuTouchScrollEnabled)
    }
}
