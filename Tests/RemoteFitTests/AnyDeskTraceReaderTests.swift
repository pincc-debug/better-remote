import Foundation
import XCTest
import RemoteFitCore
@testable import RemoteFit

final class AnyDeskTraceReaderTests: XCTestCase {
    func testLiveAnyDeskSnapshotWhenRequested() async throws {
        guard let expected = ProcessInfo.processInfo.environment["BETTER_REMOTE_TEST_ANYDESK"] else {
            throw XCTSkip("Requires a user-controlled AnyDesk session")
        }
        let snapshot = await RemoteSessionProbe().sample()
        XCTAssertFalse(snapshot.unknown.contains(.anyDesk))
        XCTAssertEqual(snapshot.active.contains(.anyDesk), expected == "connected")
    }

    private let birth = Date(timeIntervalSince1970: 1_792_465_600)
    private func line(_ message: String) -> String {
        "info 2026-10-20 03:07:51.010 lsvc main 58802 1683926 27 app.session - \(message)\n"
    }
    private var pending: String {
        line("Session features: deskrt, clipboard.") + line("Backend PID: 82225") + line("2: Requesting a session at the backend.")
    }
    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testIncrementalPartialLinesAndRestartReplay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("anydesk.trace")
        try pending.write(to: url, atomically: true, encoding: .utf8)
        var reader = AnyDeskTraceReader(url: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .disconnected)
        let start = line("5: Entering processing loop.")
        try append(String(start.dropLast(5)), to: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .disconnected)
        try append(String(start.suffix(5)), to: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .connected)
        var restarted = AnyDeskTraceReader(url: url)
        XCTAssertEqual(restarted.sample(backends: [82225: birth]), .connected)
        try append(line("5: Processing done."), to: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .disconnected)
        XCTAssertEqual(restarted.sample(backends: [82225: birth]), .disconnected)
    }

    func testRotationTruncationAndMissingFileCannotInventDisconnect() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("anydesk.trace")
        var reader = AnyDeskTraceReader(url: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .unknown)
        try (pending + line("5: Entering processing loop.")).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .connected)
        try pending.write(to: url, atomically: true, encoding: .utf8) // new inode
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .unknown)
        try append(line("5: Entering processing loop."), to: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .connected)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0); try handle.close()
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .unknown)
        XCTAssertEqual(reader.sample(backends: [:]), .disconnected)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .unknown)
    }

    func testProbeRequiresOwnedActiveAssertionAndKeepsPollingPendingAuthorization() {
        let path = "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
        let name = RemoteSessionEvidence.anyDeskAssertionName
        XCTAssertTrue(RemoteSessionProbe.isAnyDeskRequest(executable: path, type: "NoDisplaySleepAssertion", name: name, level: 255))
        XCTAssertFalse(RemoteSessionProbe.isAnyDeskRequest(executable: path + "Other", type: "NoDisplaySleepAssertion", name: name, level: 255))
        XCTAssertFalse(RemoteSessionProbe.isAnyDeskRequest(executable: path, type: "UserIsActive", name: name, level: 255))
        XCTAssertFalse(RemoteSessionProbe.isAnyDeskRequest(executable: path, type: "NoDisplaySleepAssertion", name: name, level: 0))
        var snapshot = RemoteSessionSnapshot(active: [.uu])
        RemoteSessionProbe.mergeAnyDesk(.disconnected, hasRequest: true, into: &snapshot)
        XCTAssertEqual(snapshot.active, [.uu])
        XCTAssertEqual(snapshot.confirmationDelay(nil), 1)
        XCTAssertEqual(snapshot.confirmationDelay(0.2), 0.2)
        RemoteSessionProbe.mergeAnyDesk(.unknown, hasRequest: true, into: &snapshot)
        XCTAssertEqual(snapshot.unknown, [.anyDesk])
        RemoteSessionProbe.mergeAnyDesk(.connected, hasRequest: true, into: &snapshot)
        XCTAssertEqual(snapshot.active, [.uu, .anyDesk])
        XCTAssertTrue(snapshot.unknown.isEmpty)
        var idle = RemoteSessionSnapshot()
        RemoteSessionProbe.mergeAnyDesk(.connected, hasRequest: false, into: &idle)
        XCTAssertTrue(idle.active.isEmpty)
        XCTAssertNil(idle.recheckAfter)
    }

    func testInPlaceRewriteAtSameSizeInvalidatesOldSession() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = pending + line("5: Entering processing loop.")
        try original.write(to: url, atomically: true, encoding: .utf8)
        var reader = AnyDeskTraceReader(url: url)
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .connected)
        let handle = try FileHandle(forWritingTo: url)
        // Change a line near the old read offset without changing inode or size.
        try handle.write(contentsOf: Data(original.replacingOccurrences(of: "Entering processing loop.", with: "Exiting! processing loop.").utf8))
        try handle.close()
        XCTAssertEqual(reader.sample(backends: [82225: birth]), .unknown)
    }
}
