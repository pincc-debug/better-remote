import Foundation
import Darwin
import RemoteFitCore

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                    timeout: TimeInterval = 8) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteFit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("stdout")
        let error = folder.appendingPathComponent("stderr")
        let incoming = folder.appendingPathComponent("stdin")
        try Data().write(to: output); try Data().write(to: error); try (input ?? Data()).write(to: incoming)
        let out = try FileHandle(forWritingTo: output), err = try FileHandle(forWritingTo: error)
        let stdin = try FileHandle(forReadingFrom: incoming)
        defer { try? out.close(); try? err.close(); try? stdin.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = out; process.standardError = err; process.standardInput = stdin
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw FitError.message("操作超时：\(URL(fileURLWithPath: executable).lastPathComponent)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: (try? Data(contentsOf: error)) ?? Data(), as: UTF8.self)
            throw FitError.message(String(detail.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? "操作失败（\(process.terminationStatus)）" : String(detail.prefix(700)))
        }
        return try Data(contentsOf: output)
    }
}
