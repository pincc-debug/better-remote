import XCTest
@testable import RemoteFitCore

final class AnyDeskSessionLogTests: XCTestCase {
    private let birth = Date(timeIntervalSince1970: 1_792_465_600) // 2026-10-20 03:06:40 UTC
    private func line(_ message: String, fiber: Int = 27, role: String = "lsvc", time: String = "03:07:51.010") -> String {
        "   info 2026-10-20 \(time) \(role) main 58802 1683926 \(fiber) app.session - \(message)"
    }
    private func request(_ log: inout AnyDeskSessionLog, fiber: Int = 27, backend: Int = 82225, desktop: Bool = true) {
        for message in ["Session features: \(desktop ? "deskrt, clipboard" : "file_manager").",
                        "Backend PID: \(backend)", "2: Requesting a session at the backend."] {
            log.consume(line(message, fiber: fiber))
        }
    }

    func testRequestAuthenticationAndCancellationNeverCountAsConnected() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("3: Authentication 65 0."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume(line("3: Authenticated by local user."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume(line("Session closed by remote side: desk_rt_ipc_error."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testSuccessfulIncomingSessionAndStopWithAssertionStillPresent() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
        XCTAssertEqual(log.status(backends: [:]), .disconnected)
        log.consume(line("5: Processing done."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testPasswordAuthenticationUsesSameReadySignal() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("3: Authentication 67 0."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume(line("3: Authenticated with correct passphrase of profile '_unattended_access'."))
        log.consume(line("4: Waiting for the backend to be ready."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume(line("4: Backend ready."))
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
    }

    func testBackendRespawnPreservesSessionAndRecognizesRecoveryWithoutNewProcessingLoop() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
        log.consume(line("IPC socket closed unexpectedly.", time: "03:09:37.972"))
        log.consume(line("Backend terminated.", time: "03:09:38.476"))
        XCTAssertEqual(log.status(backends: [82225: birth]), .unknown)
        log.consume(line("Backend PID: 24949", time: "03:09:38.572"))
        log.retain(backends: [82225]) // assertion still belongs to the old backend
        log.consume(line("2: Requesting a session at the backend.", time: "03:09:38.583"))
        let newBirth = birth.addingTimeInterval(178)
        XCTAssertEqual(log.status(backends: [24949: newBirth]), .unknown)
        log.consume(line("Backend respawn succeeded.", time: "03:09:42.555"))
        XCTAssertEqual(log.status(backends: [24949: newBirth]), .connected)
        log.consume(line("Session closed by remote side: desk_rt_ipc_error.", time: "03:09:50.000"))
        XCTAssertEqual(log.status(backends: [24949: newBirth]), .disconnected)
    }

    func testCancellingAnotherRequestCannotEndAnAcceptedSessionOnSameBackend() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("5: Entering processing loop."))
        request(&log, fiber: 43)
        log.consume(line("Session closed by remote side: desk_rt_ipc_error.", fiber: 43))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
        log.consume(line("5: Entering processing loop.", fiber: 43)) // a late line cannot reopen a closed request
        log.consume(line("5: Processing done."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testMultipleAcceptedSessionsOnlyDisconnectAfterLastEnds() {
        var log = AnyDeskSessionLog()
        for fiber in [27, 43] { request(&log, fiber: fiber); log.consume(line("5: Entering processing loop.", fiber: fiber)) }
        log.consume(line("5: Processing done.", fiber: 27))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
        log.consume(line("5: Processing done.", fiber: 43))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testOutgoingFileTransferAndRelayMessagesDoNotConnect() {
        var log = AnyDeskSessionLog()
        request(&log, desktop: false)
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume(line("Session features: deskrt."))
        log.consume(line("Backend PID: 82225"))
        log.consume(line("5: Entering processing loop.")) // no incoming backend request
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
        log.consume("info relay - Connection established.")
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testReplayedHistoryRequiresSameLiveProcessGeneration() {
        var log = AnyDeskSessionLog()
        request(&log)
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .connected)
        XCTAssertEqual(log.status(backends: [82225: birth.addingTimeInterval(1000)]), .unknown)
        XCTAssertEqual(log.status(backends: [999: birth]), .unknown)
        log.consume(line("Session features: deskrt.")) // reused fiber starts again pending
        log.consume(line("Backend PID: 82225"))
        XCTAssertEqual(log.status(backends: [82225: birth]), .disconnected)
    }

    func testUnknownFormatAndMissingSessionHistoryStayUnknown() {
        var log = AnyDeskSessionLog()
        log.consume("new version has different logging")
        XCTAssertEqual(log.status(backends: [82225: birth]), .unknown)
        log.consume(line("5: Entering processing loop."))
        XCTAssertEqual(log.status(backends: [82225: birth]), .unknown)
    }

    func testOneProviderDisconnectDoesNotRestoreWhileAnyDeskRemains() {
        var stability = RemoteSessionStability()
        _ = stability.observe(.init(active: [.uu, .anyDesk]), at: 0)
        XCTAssertEqual(stability.observe(.init(active: [.uu, .anyDesk]), at: 2), .connected)
        XCTAssertNil(stability.observe(.init(active: [.anyDesk]), at: 10))
        XCTAssertNil(stability.observe(.init(unknown: [.anyDesk]), at: 20))
        XCTAssertTrue(stability.isConnected)
        _ = stability.observe(.init(), at: 30)
        XCTAssertEqual(stability.observe(.init(), at: 31.5), .disconnected)
    }
}
