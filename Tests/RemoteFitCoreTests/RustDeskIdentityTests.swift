import XCTest
@testable import RemoteFitCore

final class RustDeskIdentityTests: XCTestCase {
    func testPeerIDParsesConnectionManagerTitleOnly() {
        XCTAssertEqual(RustDeskWindowTitle.peerID(in: "1283940661 - RustDesk"), "1283940661")
        XCTAssertEqual(RustDeskWindowTitle.peerID(in: "  1283940661 - RustDesk  "), "1283940661")
        XCTAssertEqual(RustDeskWindowTitle.peerID(in: "1283940661  -  RustDesk"), "1283940661")
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "RustDesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "1283940661"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "1283940661 - rustdesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "File Transfer - RustDesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: " - RustDesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: ""))
    }

    func testSourceAddressIsNotADeviceKey() {
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "10.8.0.1 - RustDesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "192.168.1.20 - RustDesk"))
        XCTAssertNil(RustDeskWindowTitle.peerID(in: "fd00::1 - RustDesk"))
        XCTAssertFalse(RustDeskWindowTitle.isPeerID("10.8.0.1"))
        XCTAssertFalse(RustDeskWindowTitle.isPeerID("192.168.1.20"))
    }

    func testUUAndRustDeskKeysStaySeparateForOnePhone() {
        let model = "vivoV2545A"
        let uu = RemoteDevice(id: RemoteDeviceKey.uuWindow(model), name: model)
        let rust = RemoteDeviceIdentity.rustDesk(peerID: "1283940661")
        XCTAssertEqual(uu.id, "uu:window:vivoV2545A")
        XCTAssertEqual(uu.software, .uu)
        XCTAssertEqual(rust.id, "rustdesk:id:1283940661")
        XCTAssertEqual(rust.name, "1283940661")
        XCTAssertEqual(rust.software, .rustDesk)
        XCTAssertNotEqual(uu.id, rust.id)
        XCTAssertEqual(UUWindowDeviceParser.device(in: [model, "远程控制"])?.id, uu.id)
        XCTAssertEqual(UUWindowDeviceParser.device(in: [model, "远程控制"])?.software, .uu)
    }

    func testSavedListKeepsBothRows() throws {
        var preferences = Preferences()
        let uu = RemoteDevice(id: RemoteDeviceKey.uuWindow("vivoV2545A"), name: "vivoV2545A")
        let rust = RemoteDeviceIdentity.rustDesk(peerID: "1283940661")
        preferences.remember(uu)
        preferences.remember(rust)
        preferences.renameDevice(rust.id, to: "我的手机")
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.remoteDevices.map(\.id), [uu.id, rust.id])
        XCTAssertEqual(restored.remoteDevices.map(\.software), [.uu, .rustDesk])
        XCTAssertEqual(restored.remoteDevices[1].displayName, "我的手机")
        XCTAssertEqual(restored.remoteDevices[1].name, "1283940661")
        XCTAssertEqual(restored.remoteDevices[0].configuration, preferences.configuration(for: nil))
        XCTAssertEqual(restored.remoteDevices[1].configuration, preferences.configuration(for: nil))
        var dropped = preferences
        dropped.remoteDevices.append(.init(id: "todesk:1", name: "ToDesk"))
        let filtered = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(dropped))
        XCTAssertEqual(filtered.remoteDevices.map(\.software), [.uu, .rustDesk])
    }

    func testCacheKeepsPeerIDWhileWindowIsClosedAndClearsOnDisconnect() {
        var identity = RustDeskSessionIdentity()
        let seen = identity.sample(sessionConnected: true, visiblePeerIDs: ["1283940661"])
        XCTAssertEqual(seen.sessionDevice?.id, "rustdesk:id:1283940661")
        XCTAssertEqual(identity.peerID, "1283940661")

        let minimizedStillVisible = identity.sample(sessionConnected: true, visiblePeerIDs: ["1283940661"])
        XCTAssertEqual(minimizedStillVisible.sessionDevice?.id, seen.sessionDevice?.id)

        let closed = identity.sample(sessionConnected: true, visiblePeerIDs: [])
        XCTAssertEqual(closed.sessionDevice?.id, "rustdesk:id:1283940661")
        XCTAssertEqual(closed.devices.map(\.id), ["rustdesk:id:1283940661"])

        let disconnected = identity.sample(sessionConnected: false, visiblePeerIDs: ["1283940661"])
        XCTAssertNil(disconnected.sessionDevice)
        XCTAssertTrue(disconnected.devices.isEmpty)
        XCTAssertNil(identity.peerID)

        let nextSession = identity.sample(sessionConnected: true, visiblePeerIDs: [])
        XCTAssertNil(nextSession.sessionDevice)
        XCTAssertTrue(nextSession.devices.isEmpty)
    }

    func testMultiplePeersDoNotCollapseToTheCachedID() {
        var identity = RustDeskSessionIdentity()
        _ = identity.sample(sessionConnected: true, visiblePeerIDs: ["1283940661"])
        let both = identity.sample(sessionConnected: true, visiblePeerIDs: ["222", "1283940661", "1283940661"])
        XCTAssertNil(both.sessionDevice)
        XCTAssertEqual(both.devices.map(\.id), [
            RemoteDeviceKey.rustDesk(peerID: "1283940661"),
            RemoteDeviceKey.rustDesk(peerID: "222")
        ])
        XCTAssertNil(identity.peerID)
        let windowsClosed = identity.sample(sessionConnected: true, visiblePeerIDs: [])
        XCTAssertNil(windowsClosed.sessionDevice)
        let oneLeft = identity.sample(sessionConnected: true, visiblePeerIDs: ["222"])
        XCTAssertEqual(oneLeft.sessionDevice?.id, RemoteDeviceKey.rustDesk(peerID: "222"))
    }

    func testUnreadableSampleDoesNotCarryAnotherSoftwaresProfile() {
        let uu = RemoteDevice(id: RemoteDeviceKey.uuWindow("手机"), name: "手机")
        let rust = RemoteDeviceIdentity.rustDesk(peerID: "1283940661")
        var uuSession = RemoteSessionSnapshot(active: [.uu])
        uuSession.uuDevice = uu
        XCTAssertEqual(RemoteSessionDeviceMatch.deviceID(in: uuSession, previous: nil), uu.id)

        var rustSession = RemoteSessionSnapshot(active: [.rustDesk])
        rustSession.rustDeskDevice = rust
        XCTAssertEqual(RemoteSessionDeviceMatch.deviceID(in: rustSession, previous: uu.id), rust.id)

        var pending = RemoteSessionSnapshot(active: [.rustDesk])
        XCTAssertNil(RemoteSessionDeviceMatch.deviceID(in: pending, previous: nil))

        var both = RemoteSessionSnapshot(active: [.uu, .rustDesk])
        both.uuDevice = uu
        both.rustDeskDevice = rust
        XCTAssertNil(RemoteSessionDeviceMatch.deviceID(in: both, previous: uu.id))

        let rustUnknown = RemoteSessionSnapshot(unknown: [.rustDesk])
        XCTAssertEqual(RemoteSessionDeviceMatch.deviceID(in: rustUnknown, previous: rust.id), rust.id)
        XCTAssertNil(RemoteSessionDeviceMatch.deviceID(in: rustUnknown, previous: uu.id))
        XCTAssertEqual(RemoteSessionDeviceMatch.deviceID(in: RemoteSessionSnapshot(unknown: [.uu]), previous: uu.id), uu.id)
    }

    func testConnectionManagerArgumentIsRustDeskCMOnly() {
        let exe = "/Applications/RustDesk.app/Contents/MacOS/RustDesk"
        XCTAssertTrue(RustDeskProcess.isConnectionManager(executable: exe, arguments: [exe, "--cm"]))
        XCTAssertFalse(RustDeskProcess.isConnectionManager(executable: exe, arguments: [exe, "--server"]))
        XCTAssertFalse(RustDeskProcess.isConnectionManager(executable: exe, arguments: [exe, "--service"]))
        XCTAssertFalse(RustDeskProcess.isConnectionManager(executable: "/usr/bin/python3", arguments: ["/usr/bin/python3", "--cm"]))
        XCTAssertEqual(RustDeskProcess.bundleIdentifier, "com.carriez.rustdesk")
    }

    func testArgumentBlobReadsArgcPathAndArguments() {
        let exe = "/Applications/RustDesk.app/Contents/MacOS/RustDesk"
        var buffer: [UInt8] = []
        var argc = Int32(2)
        withUnsafeBytes(of: &argc) { buffer.append(contentsOf: $0) }
        func appendCString(_ text: String) {
            buffer.append(contentsOf: Array(text.utf8))
            buffer.append(0)
        }
        appendCString(exe)
        buffer.append(0)
        appendCString(exe)
        appendCString("--cm")
        XCTAssertEqual(ProcessArgumentBlob.arguments(in: buffer), [exe, "--cm"])
        XCTAssertNil(ProcessArgumentBlob.arguments(in: [0, 0]))
    }
}
