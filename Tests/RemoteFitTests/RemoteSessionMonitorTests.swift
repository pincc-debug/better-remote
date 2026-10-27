import XCTest
@testable import RemoteFit
import RemoteFitCore

@MainActor
final class RemoteSessionMonitorTests: XCTestCase {
    func testInitialSampleAndOneShotConfirmationThenStop() async throws {
        let monitor = RemoteSessionMonitor()
        var samples = 0
        monitor.start {
            samples += 1
            return samples == 1 ? 0.05 : nil
        }
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertGreaterThanOrEqual(samples, 2)
        monitor.stop()
        let stopped = samples
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(samples, stopped)
    }

    func testStopCancelsInFlightConfirmation() async throws {
        let monitor = RemoteSessionMonitor()
        var samples = 0
        monitor.start {
            samples += 1
            try? await Task.sleep(for: .milliseconds(200))
            return 0.05
        }
        try await Task.sleep(for: .milliseconds(50))
        monitor.stop()
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(samples, 1)
    }

    func testConfirmationDeadlineSurvivesExtraEventsAndUnknownCancelsIt() {
        var stability = RemoteSessionStability()
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 10))
        XCTAssertEqual(stability.confirmationDelay(at: 10), 2)
        XCTAssertNil(stability.observe(.init(active: [.uu]), at: 11))
        XCTAssertEqual(stability.confirmationDelay(at: 11), 1)
        XCTAssertEqual(stability.observe(.init(active: [.uu]), at: 12), .connected)
        XCTAssertNil(stability.confirmationDelay(at: 12))
        XCTAssertNil(stability.observe(.init(), at: 13))
        XCTAssertEqual(stability.confirmationDelay(at: 13), RemoteSessionStability.disconnectConfirm)
        XCTAssertNil(stability.observe(.init(unknown: [.uu]), at: 14))
        XCTAssertNil(stability.confirmationDelay(at: 14))
        XCTAssertTrue(stability.isConnected)
    }
}
