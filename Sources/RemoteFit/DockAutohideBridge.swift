import Foundation
import RemoteFitCore

/// Thin bridge to the Dock's 自动隐藏 through System Events (the first use asks the user to allow
/// Better Remote to control 系统事件). Every script runs on one serial queue, so reads and writes keep their order
/// and the main thread never waits on Apple Events or the permission prompt.
final class DockAutohideBridge: @unchecked Sendable {
    static let shared = DockAutohideBridge()

    struct ScriptError: LocalizedError {
        let code: Int
        let message: String
        /// errAEEventNotPermitted: the user declined (or has not yet allowed) control of 系统事件.
        var isPermissionDenied: Bool { code == -1743 || code == -10004 }
        var errorDescription: String? {
            isPermissionDenied
                ? "请在“系统设置 › 隐私与安全性 › 自动化”中允许 Better Remote 控制“系统事件”。"
                : "\(message) (\(code))"
        }
    }

    private let queue = DispatchQueue(label: "local.RemoteFit.dock-autohide", qos: .userInitiated)
    private static let persistedKey = "ConnectionDockOriginalAutohide"

    /// The user's own value while we owe it back; survives a crash so the next launch can restore it.
    static var persistedOriginal: Bool? {
        get { UserDefaults.standard.object(forKey: persistedKey) as? Bool }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: persistedKey) }
            else { UserDefaults.standard.removeObject(forKey: persistedKey) }
        }
    }

    func read() async throws -> Bool {
        try await run { try Self.readNow() }
    }

    func write(_ autohide: Bool) async throws {
        try await run { try Self.writeNow(autohide) }
    }

    /// Quit path: after any queued write, give back the persisted original (if still owed) and clear it.
    /// Blocks the calling (non-main) thread.
    func restorePersistedNow() -> String {
        queue.sync {
            guard let original = Self.persistedOriginal else { return "nothing_owed" }
            do {
                let current = try Self.readNow()
                var session = ConnectionDockSession(originalAutohide: original)
                if let value = session.restore(current: current) { try Self.writeNow(value) }
                Self.persistedOriginal = nil
                return "restored autohide=\(original)"
            } catch {
                return "restore_failed \(error.localizedDescription)"
            }
        }
    }

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private static func readNow() throws -> Bool {
        try execute("tell application \"System Events\" to get autohide of dock preferences").booleanValue
    }

    private static func writeNow(_ autohide: Bool) throws {
        _ = try execute("tell application \"System Events\" to set autohide of dock preferences to \(autohide ? "true" : "false")")
    }

    private static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw ScriptError(code: -2700, message: "脚本无法创建") }
        var info: NSDictionary?
        let result = script.executeAndReturnError(&info)
        if let info {
            let code = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            let message = info[NSAppleScript.errorMessage] as? String ?? "程序坞设置失败"
            throw ScriptError(code: code, message: message)
        }
        return result
    }
}
