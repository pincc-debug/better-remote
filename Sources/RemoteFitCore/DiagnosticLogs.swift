import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Fields written to `meta.json` inside a diagnostic archive.
struct DiagnosticLogMeta: Codable, Equatable, Sendable {
    var version: String
    var build: String
    var macos: String
    var hostname: String?
    var model: String?
    var timestamp: String
    var bundleID: String

    private enum CodingKeys: String, CodingKey {
        case version, build, macos, hostname, model, timestamp, bundleID
    }

    init(version: String, build: String, macos: String, hostname: String?, model: String?, timestamp: String, bundleID: String) {
        self.version = version
        self.build = build
        self.macos = macos
        self.hostname = hostname
        self.model = model
        self.timestamp = timestamp
        self.bundleID = bundleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        build = try container.decode(String.self, forKey: .build)
        macos = try container.decode(String.self, forKey: .macos)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        bundleID = try container.decode(String.self, forKey: .bundleID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(build, forKey: .build)
        try container.encode(macos, forKey: .macos)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(bundleID, forKey: .bundleID)
    }
}

/// Builds a zip of the app's own logs. Missing files are skipped.
/// Typed input and clipboard contents are never read.
enum DiagnosticLogArchive {
    /// Product names, plus the rotated names this app actually writes
    /// (`RemoteFit.previous.log`, `WindowActions.previous.log`).
    static let packagedFileNames = [
        "RemoteFit.log",
        "RemoteFit.log.previous",
        "RemoteFit.previous.log",
        "Operations.log",
        "WindowActions.log",
        "WindowActions.log.previous",
        "WindowActions.previous.log"
    ]

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RemoteFit", isDirectory: true)
    }

    static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func currentMeta(bundle: Bundle = .main, now: Date = Date()) -> DiagnosticLogMeta {
        let info = bundle.infoDictionary
        func text(_ key: String) -> String? {
            guard let value = info?[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return DiagnosticLogMeta(
            version: text("CFBundleShortVersionString") ?? "",
            build: text("CFBundleVersion") ?? "",
            macos: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            hostname: host.isEmpty ? nil : host,
            model: machineModel(),
            timestamp: timestamp(for: now),
            bundleID: bundle.bundleIdentifier ?? "local.RemoteFit"
        )
    }

    static func machineModel() -> String? {
        #if canImport(Darwin)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let model = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
        #else
        return nil
        #endif
    }

    /// Zip of whichever packaged logs exist in `directory`, plus `meta.json`.
    static func makeZip(directory: URL, meta: DiagnosticLogMeta) -> Data {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var files: [(String, Data)] = []
        for name in packagedFileNames {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  data.count <= Int(UInt32.max) else { continue }
            files.append((name, data))
        }
        files.append(("meta.json", encoded(meta)))
        return ZipStore.archive(files)
    }

    /// Uncompressed entries, for tests. Returns nil when the archive is not a store-method zip we wrote.
    static func entries(in archive: Data) -> [String: Data]? {
        ZipStore.entries(in: archive)
    }

    private static func encoded(_ meta: DiagnosticLogMeta) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(meta), !data.isEmpty { return data }
        return Data(#"{"version":"","build":"","macos":"","timestamp":"","bundleID":""}"#.utf8)
    }
}

enum DiagnosticLogError: Error, Equatable {
    case emptyMessage
    case rejected
}

protocol DiagnosticLogTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionDiagnosticLogTransport: DiagnosticLogTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DiagnosticLogError.rejected }
        return (data, http.statusCode)
    }
}

/// POST BetterRemoteSite.diagnosticLogs
public enum DiagnosticLogUpload {
    static let endpoint = BetterRemoteSite.diagnosticLogs
    static let archiveName = "diagnostic-logs.zip"

    static func submit(
        message: String,
        attachLogs: Bool,
        directory: URL,
        meta: DiagnosticLogMeta,
        endpoint: URL,
        transport: any DiagnosticLogTransport
    ) async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DiagnosticLogError.emptyMessage }
        let file: Data?
        if attachLogs {
            file = await Task.detached {
                DiagnosticLogArchive.makeZip(directory: directory, meta: meta)
            }.value
        } else {
            file = nil
        }
        let request = formRequest(message: text, file: file, endpoint: endpoint)
        let data: Data
        let status: Int
        do {
            (data, status) = try await transport.send(request)
        } catch let error as DiagnosticLogError {
            throw error
        } catch {
            throw DiagnosticLogError.rejected
        }
        guard let id = identifier(status: status, body: data) else { throw DiagnosticLogError.rejected }
        return id
    }

    /// Sends feedback. When `attachLogs` is true, the body includes `diagnostic-logs.zip`.
    public static func submit(message: String, attachLogs: Bool) async throws -> String {
        try await submit(
            message: message,
            attachLogs: attachLogs,
            directory: DiagnosticLogArchive.supportDirectory,
            meta: DiagnosticLogArchive.currentMeta(),
            endpoint: endpoint,
            transport: URLSessionDiagnosticLogTransport()
        )
    }

    static func formRequest(message: String, file: Data?, endpoint: URL) -> URLRequest {
        let boundary = boundaryString(message: message, file: file)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(message: message, file: file, boundary: boundary)
        return request
    }

    static func identifier(status: Int, body: Data) -> String? {
        guard (200..<300).contains(status) else { return nil }
        struct Body: Decodable { var id: String }
        guard let id = try? JSONDecoder().decode(Body.self, from: body).id else { return nil }
        guard id.hasPrefix("br-"), id.count > 3, id.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return id
    }

    private static func boundaryString(message: String, file: Data?) -> String {
        let messageData = Data(message.utf8)
        var boundary = "BetterRemote-\(UUID().uuidString)"
        while messageData.range(of: Data(boundary.utf8)) != nil || file?.range(of: Data(boundary.utf8)) != nil {
            boundary = "BetterRemote-\(UUID().uuidString)"
        }
        return boundary
    }

    private static func formBody(message: String, file: Data?, boundary: String) -> Data {
        var body = Data()
        func line(_ value: String) { body.append(Data(value.utf8)) }
        line("--\(boundary)\r\n")
        line("Content-Disposition: form-data; name=\"message\"\r\n")
        line("Content-Type: text/plain; charset=utf-8\r\n\r\n")
        body.append(Data(message.utf8))
        line("\r\n")
        if let file {
            line("--\(boundary)\r\n")
            line("Content-Disposition: form-data; name=\"file\"; filename=\"\(archiveName)\"\r\n")
            line("Content-Type: application/zip\r\n\r\n")
            body.append(file)
            line("\r\n")
        }
        line("--\(boundary)--\r\n")
        return body
    }
}

/// Store-method zip (no compression). Log files are already small and rotated.
enum ZipStore {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let version: UInt16 = 20
    private static let utf8Flag: UInt16 = 1 << 11
    /// 2026-10-26 00:00 in DOS date format.
    private static let dosDate: UInt16 = ((2026 - 1980) << 9) | (10 << 5) | 26

    static func archive(_ files: [(String, Data)]) -> Data {
        var local = Data()
        var items: [(name: String, data: Data, crc: UInt32, offset: UInt32)] = []
        for (name, data) in files {
            guard data.count <= Int(UInt32.max), local.count <= Int(UInt32.max) else { continue }
            let nameData = Data(name.utf8)
            guard nameData.count <= Int(UInt16.max) else { continue }
            let offset = UInt32(local.count)
            let crc = crc32(data)
            appendLocal(into: &local, name: nameData, data: data, crc: crc)
            items.append((name, data, crc, offset))
        }
        let centralOffset = UInt32(local.count)
        var central = Data()
        for item in items {
            appendCentral(into: &central, name: Data(item.name.utf8), data: item.data, crc: item.crc, offset: item.offset)
        }
        let centralSize = UInt32(central.count)
        appendEnd(into: &central, count: UInt16(items.count), centralSize: centralSize, centralOffset: centralOffset)
        local.append(central)
        return local
    }

    static func entries(in archive: Data) -> [String: Data]? {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { return nil }
        var endIndex: Int?
        var index = bytes.count - 22
        let lower = max(0, bytes.count - 22 - 65_535)
        while index >= lower {
            if uint32(bytes, index) == endSignature {
                endIndex = index
                break
            }
            if index == 0 { break }
            index -= 1
        }
        guard let endIndex else { return nil }
        let total = Int(uint16(bytes, endIndex + 10))
        let centralSize = Int(uint32(bytes, endIndex + 12))
        let centralOffset = Int(uint32(bytes, endIndex + 16))
        guard centralOffset <= bytes.count, bytes.count - centralOffset >= centralSize else { return nil }
        var result: [String: Data] = [:]
        var cursor = centralOffset
        let centralEnd = centralOffset + centralSize
        for _ in 0..<total {
            guard cursor + 46 <= centralEnd, uint32(bytes, cursor) == centralSignature else { return nil }
            let method = uint16(bytes, cursor + 10)
            let crc = uint32(bytes, cursor + 16)
            let compressedSize = Int(uint32(bytes, cursor + 20))
            let nameLength = Int(uint16(bytes, cursor + 28))
            let extraLength = Int(uint16(bytes, cursor + 30))
            let commentLength = Int(uint16(bytes, cursor + 32))
            let localOffset = Int(uint32(bytes, cursor + 42))
            guard method == 0, cursor + 46 + nameLength <= centralEnd else { return nil }
            let nameData = Data(bytes[(cursor + 46)..<(cursor + 46 + nameLength)])
            guard let name = String(data: nameData, encoding: .utf8) else { return nil }
            guard localOffset + 30 <= bytes.count, uint32(bytes, localOffset) == localSignature else { return nil }
            let localNameLength = Int(uint16(bytes, localOffset + 26))
            let localExtraLength = Int(uint16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart <= bytes.count, compressedSize <= bytes.count - dataStart else { return nil }
            let dataEnd = dataStart + compressedSize
            let data = Data(bytes[dataStart..<dataEnd])
            guard crc32(data) == crc else { return nil }
            result[name] = data
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard cursor == centralEnd else { return nil }
        return result
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func appendLocal(into data: inout Data, name: Data, data file: Data, crc: UInt32) {
        append(localSignature, to: &data)
        append(version, to: &data)
        append(utf8Flag, to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(dosDate, to: &data)
        append(crc, to: &data)
        append(UInt32(file.count), to: &data)
        append(UInt32(file.count), to: &data)
        append(UInt16(name.count), to: &data)
        append(UInt16(0), to: &data)
        data.append(name)
        data.append(file)
    }

    private static func appendCentral(into data: inout Data, name: Data, data file: Data, crc: UInt32, offset: UInt32) {
        append(centralSignature, to: &data)
        append(version, to: &data)
        append(version, to: &data)
        append(utf8Flag, to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(dosDate, to: &data)
        append(crc, to: &data)
        append(UInt32(file.count), to: &data)
        append(UInt32(file.count), to: &data)
        append(UInt16(name.count), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(0), to: &data)
        append(offset, to: &data)
        data.append(name)
    }

    private static func appendEnd(into data: inout Data, count: UInt16, centralSize: UInt32, centralOffset: UInt32) {
        append(endSignature, to: &data)
        append(UInt16(0), to: &data)
        append(UInt16(0), to: &data)
        append(count, to: &data)
        append(count, to: &data)
        append(centralSize, to: &data)
        append(centralOffset, to: &data)
        append(UInt16(0), to: &data)
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
