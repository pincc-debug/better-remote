import AppKit
import XCTest
import RemoteFitCore
@testable import RemoteFit

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func scan() -> [ApplicationWindowCatalog.Window] {
        XCTAssertFalse(Thread.isMainThread)
        lock.lock(); value += 1; lock.unlock()
        Thread.sleep(forTimeInterval: 0.05)
        return [.init(pid: 12, id: 34, frame: CGRect(x: 0, y: 0, width: 400, height: 300))]
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class PerformanceRegressionTests: XCTestCase {
    func testWindowConsumersShareOneScanAndExpireSnapshot() async {
        let counter = ScanCounter()
        var now: TimeInterval = 100
        let catalog = ApplicationWindowCatalog(query: { counter.scan() }, uptime: { now })
        async let first = catalog.snapshot()
        async let second = catalog.snapshot()
        let results = await (first, second)
        XCTAssertEqual(results.0, results.1)
        XCTAssertEqual(counter.count, 1)
        _ = await catalog.snapshot()
        XCTAssertEqual(counter.count, 1)
        now += 0.21
        _ = await catalog.snapshot()
        XCTAssertEqual(counter.count, 2)
    }

    func testIdleAndUUConnectionNeverEnumerateProcesses() {
        let idle = RemoteSessionProbe.resolve(assertions: []) {
            XCTFail("Idle must not enumerate processes"); return nil
        }
        XCTAssertTrue(idle.active.isEmpty)
        XCTAssertTrue(idle.unknown.isEmpty)
        let uu = RemotePowerAssertion(executable: "/Applications/UURemote.app/Contents/Helpers/UURemoteServer",
                                     type: "PreventUserIdleDisplaySleep", name: "idleDisplaySleepDisabled", level: 255)
        let connected = RemoteSessionProbe.resolve(assertions: [uu]) {
            XCTFail("UU must not enumerate ToDesk processes"); return nil
        }
        XCTAssertEqual(connected.active, [.uu])
    }

    func testToDeskStillRequiresProcessAndActiveAssertionAndPreservesUnknown() {
        let assertion = RemotePowerAssertion(executable: "/Applications/ToDesk.app/Contents/MacOS/ToDesk_Service",
                                            type: "PreventUserIdleDisplaySleep", name: "Preventing display sleep for app", level: 255)
        let path = "/Applications/ToDesk.app/Contents/Helpers/ToDesk_Session.app/Contents/MacOS/ToDesk_Session"
        XCTAssertEqual(RemoteSessionProbe.resolve(assertions: [assertion]) { [path] }.active, [.toDesk])
        XCTAssertTrue(RemoteSessionProbe.resolve(assertions: [assertion]) { [] }.active.isEmpty)
        XCTAssertEqual(RemoteSessionProbe.resolve(assertions: [assertion]) { nil }.unknown, [.toDesk])
        var inactive = assertion
        inactive.level = 0
        XCTAssertTrue(RemoteSessionProbe.resolve(assertions: [inactive]) {
            XCTFail("Inactive assertion must not trigger a scan"); return [path]
        }.active.isEmpty)
    }

    func testDisabledWorkspaceDiscardsInFlightWindowQuery() async throws {
        var release: CheckedContinuation<[ApplicationWindowCatalog.Window], Never>?
        var moves = 0
        let controller = WorkspaceLayoutController(visibleWindows: {
            await withCheckedContinuation { release = $0 }
        }, canAdjust: { true }, userInteracting: { false }, move: { _, _ in moves += 1 })
        controller.region = {
            .init(area: CGRect(x: 0, y: 0, width: 900, height: 800), screen: CGRect(x: 0, y: 0, width: 1000, height: 800),
                  toolbar: CGRect(x: 900, y: 0, width: 100, height: 800), side: .right)
        }
        controller.setEnabled(true)
        let deadline = ContinuousClock.now + .seconds(2)
        while release == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let continuation = try XCTUnwrap(release)
        controller.cancel()
        continuation.resume(returning: [.init(pid: 12, id: 34, frame: CGRect(x: 700, y: 0, width: 300, height: 400))])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(moves, 0)
    }

    func testFramePollingStaysOnWorkerActorAndCancellationStopsReads() async throws {
        let worker = FramePollingWorker()
        let pending = Task { try await worker.wait() }
        try await Task.sleep(for: .milliseconds(80))
        // The UI actor can run while the worker polls, then cancel before another write.
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let reads = await worker.reads
        XCTAssertGreaterThan(reads, 0)
        try await Task.sleep(for: .milliseconds(80))
        let after = await worker.reads
        XCTAssertEqual(after, reads)
    }
}

private actor FramePollingWorker {
    var reads = 0
    func wait() async throws -> CGRect {
        try await WindowLayout.waitForFrame(target: CGRect(x: 0, y: 0, width: 500, height: 500)) {
            XCTAssertFalse(Thread.isMainThread)
            self.reads += 1
            return .zero
        }
    }
}
