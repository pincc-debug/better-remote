import Foundation
import Darwin
import RemoteFitCore

/// Bounded, incremental reads on RemoteSessionProbe's actor, only while AnyDesk
/// holds a live connection-request assertion. Never reads credentials/config files.
struct AnyDeskTraceReader {
    let url: URL
    private var identity: UInt64?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var log = AnyDeskSessionLog()
    private var incompleteHistory = false
    private var checkpoint = Data()
    private let limit = 8 * 1024 * 1024

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".anydesk/anydesk.trace")) {
        self.url = url
    }

    mutating func sample(backends: [Int32: Date]) -> AnyDeskSessionLog.Status {
        guard !backends.isEmpty else { reset(); return .disconnected }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var info = stat()
            guard fstat(file.fileDescriptor, &info) == 0, info.st_size >= 0 else { return .unknown }
            let inode = UInt64(info.st_ino)
            let size = UInt64(info.st_size)
            if identity != inode || size < offset {
                let wasReading = identity != nil
                reset(); identity = inode; incompleteHistory = wasReading
            }
            if !checkpoint.isEmpty, offset >= UInt64(checkpoint.count) {
                try file.seek(toOffset: offset - UInt64(checkpoint.count))
                if try file.read(upToCount: checkpoint.count) != checkpoint {
                    // Some clients rewrite a truncated log in-place and it can
                    // grow past our old offset before the next sample.
                    reset(); identity = inode; incompleteHistory = true
                }
            }
            var skipFirst = false
            if size - offset > UInt64(limit) {
                // Unknown if the start of a long-running session has already rotated
                // away; never infer connection from a bare power assertion.
                log = AnyDeskSessionLog(); partial.removeAll()
                incompleteHistory = true
                offset = size - UInt64(limit)
                skipFirst = true
            }
            try file.seek(toOffset: offset)
            let chunk = try file.read(upToCount: Int(size - offset)) ?? Data()
            guard chunk.count == Int(size - offset) else { reset(); return .unknown }
            offset += UInt64(chunk.count)
            if !chunk.isEmpty { checkpoint = Data(chunk.suffix(128)) }
            partial.append(chunk)
            while let newline = partial.firstIndex(of: 10) {
                let line = partial[..<newline]
                if !skipFirst, let text = String(data: line, encoding: .utf8) { log.consume(text) }
                skipFirst = false
                partial.removeSubrange(...newline)
            }
            guard partial.count <= 64 * 1024 else { reset(); return .unknown }
            log.retain(backends: Set(backends.keys))
            let result = log.status(backends: backends)
            return incompleteHistory && result != .connected ? .unknown : result
        } catch {
            return .unknown
        }
    }

    mutating func reset() {
        identity = nil; offset = 0; partial.removeAll(); log = AnyDeskSessionLog(); incompleteHistory = false; checkpoint.removeAll()
    }
}
