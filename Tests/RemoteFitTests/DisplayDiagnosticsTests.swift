import XCTest
import RemoteFitCore
@testable import RemoteFit

extension DisplayEngine {
    func seedDiagnosticTest(_ value: Dimensions?) { applied = value }
}

final class DisplayDiagnosticsTests: XCTestCase {
    func testObservationOnlyReadsWorkerSnapshot() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let worker = folder.appendingPathComponent("worker")
        let script = "#!/bin/sh\n[ \"$1\" = \"--worker\" ] && [ \"$2\" = \"snapshot\" ] || exit 43\nprintf '[]'\n"
        try Data(script.utf8).write(to: worker)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
        let engine = DisplayEngine(root: folder, executable: worker.path)
        let target = Dimensions(589, 1278)
        await engine.seedDiagnosticTest(target)
        await engine.recordDisplayObservation(expected: target, sequence: 1, reason: "test", elapsed: 5,
                                              appKit: "frame=2560x1440", connection: "connected=true")
        let log = try String(contentsOf: folder.appendingPathComponent("RemoteFit.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("display_observation sequence=1"))
        XCTAssertTrue(log.contains("expected=589×1278"))
        XCTAssertTrue(log.contains("appkit={frame=2560x1440}"))
        XCTAssertFalse(log.contains("display_observation_failed"))
    }

    func testFailedProbeDoesNotThrowOrChangeAppliedMode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = DisplayEngine(root: folder, executable: "/usr/bin/false")
        let target = Dimensions(589, 1278)
        await engine.seedDiagnosticTest(target)
        await engine.recordDisplayObservation(expected: target, sequence: 2, reason: "test", elapsed: 1,
                                              appKit: "", connection: "")
        let applied = await engine.applied
        XCTAssertEqual(applied, target)
        let log = try String(contentsOf: folder.appendingPathComponent("RemoteFit.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("display_observation_failed"))
    }
}
