import XCTest
import RemoteFitCore
@testable import RemoteFit

@MainActor
final class UUWindowIdentificationTests: XCTestCase {
    private actor Access: UUWindowAccess {
        var states: [UUWindowInspection]
        var events: [String] = []
        var online = true
        let minimizeOK: Bool
        init(_ states: [UUWindowInspection], minimizeOK: Bool = true) { self.states = states; self.minimizeOK = minimizeOK }
        func inspect() -> UUWindowInspection {
            events.append("read")
            if states.count > 1 { return states.removeFirst() }
            return states.first ?? .init(hasWindow: true)
        }
        func open() -> Bool { events.append("open"); return true }
        func minimize() -> Bool { events.append("minimize"); return minimizeOK }
        func connected() -> Bool { online }
        func recorded() -> [String] { events }
    }
    private let phone = RemoteDevice(id: "uu:window:手机", name: "手机")

    func testOpensReadsAndMinimizesBeforeReturningDevice() async {
        let access = Access([.init(), .init(hasWindow: true, devices: [phone])])
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertEqual(result.device, phone)
        XCTAssertEqual(result.minimized, true)
        let events = await access.recorded()
        XCTAssertEqual(events, ["read", "open", "read", "minimize"])
    }
    func testAlreadyOpenWindowIsLeftUntouched() async {
        let access = Access([.init(hasWindow: true, devices: [phone])])
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertEqual(result.device, phone)
        let events = await access.recorded()
        XCTAssertEqual(events, ["read"])
        XCTAssertNil(result.minimized)
    }
    func testTimeoutMinimizesOpenedWindowAndDoesNotInventDevice() async {
        let access = Access([.init()])
        let result = await UUWindowIdentification.run(access: access, timeout: 0)
        XCTAssertNil(result.device)
        XCTAssertEqual(result.status, "timeout")
        let events = await access.recorded()
        XCTAssertEqual(events.last, "minimize")
    }
    func testMinimizeFailurePreservesDevice() async {
        let access = Access([.init(), .init(hasWindow: true, devices: [phone])], minimizeOK: false)
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertEqual(result.device, phone)
        XCTAssertEqual(result.minimized, false)
        XCTAssertEqual(result.status, "read")
    }
    func testCancellationStillMinimizesOpenedWindow() async {
        let access = Access([.init()])
        let task = Task { await UUWindowIdentification.run(access: access) }
        for _ in 0..<100 {
            if await access.recorded().contains("open") { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result.device)
        XCTAssertEqual(result.status, "cancelled")
        let events = await access.recorded()
        XCTAssertEqual(events.last, "minimize")
    }
    func testMultipleControllersUseNoDeviceRule() async {
        let access = Access([.init(hasWindow: true, devices: [phone, .init(id: "uu:window:平板", name: "平板")])])
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertNil(result.device)
        XCTAssertEqual(result.status, "multiple_controllers")
    }

    func testPermissionMissingOnlyWhenNotTrusted() async {
        let access = Access([.init(permitted: false, axAvailable: false)])
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertNil(result.device)
        XCTAssertEqual(result.status, "permission_missing")
        let events = await access.recorded()
        XCTAssertEqual(events, ["read"])
    }

    func testAxUnavailableIsNotPermissionMissing() async {
        let access = Access([.init(permitted: true, axAvailable: false)])
        let result = await UUWindowIdentification.run(access: access, timeout: 0)
        XCTAssertNil(result.device)
        XCTAssertEqual(result.status, "ax_unavailable")
        let events = await access.recorded()
        // Initial inspect + 2 silent retries
        XCTAssertEqual(events.filter { $0 == "read" }.count, 3)
        XCTAssertFalse(events.contains("minimize"))
    }

    func testAxUnavailableRecoversOnSilentRetry() async {
        let access = Access([
            .init(permitted: true, axAvailable: false),
            .init(permitted: true, axAvailable: false),
            .init(hasWindow: true, devices: [phone])
        ])
        let result = await UUWindowIdentification.run(access: access)
        XCTAssertEqual(result.device, phone)
        XCTAssertEqual(result.status, "read")
        let events = await access.recorded()
        XCTAssertEqual(events, ["read", "read", "read"])
    }
}
