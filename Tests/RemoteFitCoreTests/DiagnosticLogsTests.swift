import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import RemoteFitCore

final class DiagnosticLogsTests: XCTestCase {
    private func meta(hostname: String? = "studio", model: String? = "Mac16,1") -> DiagnosticLogMeta {
        DiagnosticLogMeta(
            version: "0.8.160",
            build: "179",
            macos: "15.7.1",
            hostname: hostname,
            model: model,
            timestamp: DiagnosticLogArchive.timestamp(for: Date(timeIntervalSince1970: 0)),
            bundleID: "local.RemoteFit"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic-logs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testTimestampIsUTCInternetDate() {
        XCTAssertEqual(DiagnosticLogArchive.timestamp(for: Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        XCTAssertEqual(ZipStore.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testArchiveIncludesExistingLogsAndMetaAndSkipsEverythingElse() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logs: [(String, String)] = [
            ("RemoteFit.log", "display_commit sample"),
            ("RemoteFit.log.previous", "engine alias previous"),
            ("RemoteFit.previous.log", "previous engine"),
            ("Operations.log", "drag-scroll sample"),
            ("WindowActions.log", "window action"),
            ("WindowActions.log.previous", "window previous alias"),
            ("WindowActions.previous.log", "window previous"),
            ("preferences.json", "pref-secret"),
            ("clipboard.txt", "clipboard-secret"),
            ("keyboard-input.txt", "keyboard-secret")
        ]
        for (name, text) in logs {
            try Data(text.utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Backups", isDirectory: true), withIntermediateDirectories: true)
        try Data("backup-secret".utf8).write(to: root.appendingPathComponent("Backups/RemoteFit.log"))

        let archive = DiagnosticLogArchive.makeZip(directory: root, meta: meta())
        let entries = try XCTUnwrap(DiagnosticLogArchive.entries(in: archive))
        XCTAssertEqual(Set(entries.keys), [
            "RemoteFit.log",
            "RemoteFit.log.previous",
            "RemoteFit.previous.log",
            "Operations.log",
            "WindowActions.log",
            "WindowActions.log.previous",
            "WindowActions.previous.log",
            "meta.json"
        ])
        XCTAssertEqual(entries["RemoteFit.log"], Data("display_commit sample".utf8))
        XCTAssertEqual(entries["RemoteFit.log.previous"], Data("engine alias previous".utf8))
        XCTAssertEqual(entries["RemoteFit.previous.log"], Data("previous engine".utf8))
        XCTAssertEqual(entries["Operations.log"], Data("drag-scroll sample".utf8))
        XCTAssertEqual(entries["WindowActions.previous.log"], Data("window previous".utf8))
        XCTAssertNil(archive.range(of: Data("pref-secret".utf8)))
        XCTAssertNil(archive.range(of: Data("clipboard-secret".utf8)))
        XCTAssertNil(archive.range(of: Data("keyboard-secret".utf8)))
        XCTAssertNil(archive.range(of: Data("backup-secret".utf8)))

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(entries["meta.json"])) as? [String: Any])
        XCTAssertEqual(object["version"] as? String, "0.8.160")
        XCTAssertEqual(object["build"] as? String, "179")
        XCTAssertEqual(object["macos"] as? String, "15.7.1")
        XCTAssertEqual(object["hostname"] as? String, "studio")
        XCTAssertEqual(object["model"] as? String, "Mac16,1")
        XCTAssertEqual(object["timestamp"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(object["bundleID"] as? String, "local.RemoteFit")
    }

    func testMissingFilesAndSymlinksDoNotFailOrLeak() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside-secret.txt")
        try Data("outside-secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("RemoteFit.log"), withDestinationURL: outside)
        try Data("kept".utf8).write(to: root.appendingPathComponent("Operations.log"))

        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        let empty = DiagnosticLogArchive.makeZip(directory: missing, meta: meta(hostname: nil, model: nil))
        let emptyEntries = try XCTUnwrap(DiagnosticLogArchive.entries(in: empty))
        XCTAssertEqual(Set(emptyEntries.keys), ["meta.json"])
        let emptyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(emptyEntries["meta.json"])) as? [String: Any])
        XCTAssertNil(emptyObject["hostname"])
        XCTAssertNil(emptyObject["model"])
        XCTAssertFalse(emptyObject.keys.contains("hostname"))
        XCTAssertFalse(emptyObject.keys.contains("model"))

        let archive = DiagnosticLogArchive.makeZip(directory: root, meta: meta(hostname: nil, model: "Mac14,6"))
        let entries = try XCTUnwrap(DiagnosticLogArchive.entries(in: archive))
        XCTAssertEqual(Set(entries.keys), ["Operations.log", "meta.json"])
        XCTAssertNil(archive.range(of: Data("outside-secret".utf8)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(entries["meta.json"])) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "Mac14,6")
        XCTAssertNil(object["hostname"])
    }

    func testFormCarriesMessageAndOptionalZip() throws {
        let zip = Data("zip-bytes".utf8)
        let withFile = DiagnosticLogUpload.formRequest(message: "屏幕闪了一下", file: zip, endpoint: DiagnosticLogUpload.endpoint)
        XCTAssertEqual(withFile.httpMethod, "POST")
        XCTAssertEqual(withFile.url, URL(string: "https://betterremote.pincc.dev/api/diagnostic-logs"))
        let contentType = try XCTUnwrap(withFile.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = try XCTUnwrap(withFile.httpBody)
        XCTAssertNotNil(body.range(of: Data("name=\"message\"".utf8)))
        XCTAssertNotNil(body.range(of: Data("屏幕闪了一下".utf8)))
        XCTAssertNotNil(body.range(of: Data("name=\"file\"; filename=\"diagnostic-logs.zip\"".utf8)))
        XCTAssertNotNil(body.range(of: Data("Content-Type: application/zip".utf8)))
        XCTAssertNotNil(body.range(of: zip))

        let messageOnly = DiagnosticLogUpload.formRequest(message: "只要反馈", file: nil, endpoint: DiagnosticLogUpload.endpoint)
        let messageBody = try XCTUnwrap(messageOnly.httpBody)
        XCTAssertNotNil(messageBody.range(of: Data("只要反馈".utf8)))
        XCTAssertNil(messageBody.range(of: Data("name=\"file\"".utf8)))
        XCTAssertNil(messageBody.range(of: Data("diagnostic-logs.zip".utf8)))
    }

    func testIdentifierAcceptsShortCodeOnSuccess() {
        XCTAssertEqual(DiagnosticLogUpload.identifier(status: 200, body: Data(#"{"id":"br-abc12345"}"#.utf8)), "br-abc12345")
        XCTAssertEqual(DiagnosticLogUpload.identifier(status: 201, body: Data(#"{"id":"br-1","extra":true}"#.utf8)), "br-1")
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 404, body: Data(#"{"id":"br-abc"}"#.utf8)))
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 500, body: Data()))
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 200, body: Data(#"{"error":"no"}"#.utf8)))
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 200, body: Data(#"{"id":"nope"}"#.utf8)))
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 200, body: Data(#"{"id":"br-"}"#.utf8)))
        XCTAssertNil(DiagnosticLogUpload.identifier(status: 200, body: Data("<html>br-abc</html>".utf8)))
    }

    func testSubmitPostsMessageWithoutFileUnlessLogsAreAttached() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("alpha-log".utf8).write(to: root.appendingPathComponent("RemoteFit.log"))
        try Data("clipboard-secret".utf8).write(to: root.appendingPathComponent("clipboard.txt"))
        let sample = meta()

        let plain = ScriptedTransport(status: 200, body: Data(#"{"id":"br-plain123"}"#.utf8))
        let plainID = try await DiagnosticLogUpload.submit(
            message: "  连上就黑屏  ",
            attachLogs: false,
            directory: root,
            meta: sample,
            endpoint: DiagnosticLogUpload.endpoint,
            transport: plain
        )
        XCTAssertEqual(plainID, "br-plain123")
        let plainBody = try XCTUnwrap(plain.request?.httpBody)
        XCTAssertNotNil(plainBody.range(of: Data("连上就黑屏".utf8)))
        XCTAssertNil(plainBody.range(of: Data("  连上就黑屏".utf8)))
        XCTAssertNil(plainBody.range(of: Data("name=\"file\"".utf8)))
        XCTAssertNil(plainBody.range(of: Data("alpha-log".utf8)))

        let attached = ScriptedTransport(status: 200, body: Data(#"{"id":"br-withlog1"}"#.utf8))
        let attachedID = try await DiagnosticLogUpload.submit(
            message: "连上就黑屏",
            attachLogs: true,
            directory: root,
            meta: sample,
            endpoint: DiagnosticLogUpload.endpoint,
            transport: attached
        )
        XCTAssertEqual(attachedID, "br-withlog1")
        let attachedBody = try XCTUnwrap(attached.request?.httpBody)
        XCTAssertNotNil(attachedBody.range(of: Data("filename=\"diagnostic-logs.zip\"".utf8)))
        XCTAssertNotNil(attachedBody.range(of: Data("alpha-log".utf8)))
        XCTAssertNotNil(attachedBody.range(of: Data("local.RemoteFit".utf8)))
        XCTAssertNil(attachedBody.range(of: Data("clipboard-secret".utf8)))

        let offline = ScriptedTransport(status: 200, body: Data(), error: URLError(.notConnectedToInternet))
        do {
            _ = try await DiagnosticLogUpload.submit(message: "再试一次", attachLogs: false, directory: root, meta: sample, endpoint: DiagnosticLogUpload.endpoint, transport: offline)
            XCTFail("network errors should fail the upload")
        } catch DiagnosticLogError.rejected {
        } catch {
            XCTFail("unexpected \(error)")
        }

        let missing = ScriptedTransport(status: 404, body: Data(#"{"id":"br-hidden"}"#.utf8))
        do {
            _ = try await DiagnosticLogUpload.submit(message: "再试一次", attachLogs: true, directory: root, meta: sample, endpoint: DiagnosticLogUpload.endpoint, transport: missing)
            XCTFail("non-2xx should fail the upload")
        } catch DiagnosticLogError.rejected {
        } catch {
            XCTFail("unexpected \(error)")
        }

        do {
            _ = try await DiagnosticLogUpload.submit(message: " \n ", attachLogs: true, directory: root, meta: sample, endpoint: DiagnosticLogUpload.endpoint, transport: plain)
            XCTFail("empty feedback should not upload")
        } catch DiagnosticLogError.emptyMessage {
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(plain.requestCount, 1)
    }
}

private final class ScriptedTransport: DiagnosticLogTransport, @unchecked Sendable {
    var request: URLRequest?
    var requestCount = 0
    var status: Int
    var body: Data
    var error: Error?
    init(status: Int, body: Data, error: Error? = nil) {
        self.status = status
        self.body = body
        self.error = error
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        self.request = request
        requestCount += 1
        if let error { throw error }
        return (body, status)
    }
}
