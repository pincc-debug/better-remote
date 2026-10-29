import AppKit
import ApplicationServices
import Darwin
import RemoteFitCore

/// What the probe learned about RustDesk without inventing a device.
enum RustDeskConnection: Sendable {
    /// No RustDesk client is running.
    case absent
    /// The client is running, but not `RustDesk --cm`.
    case idle
    /// A RustDesk process is there, but its arguments could not be read.
    case unknown
    /// `--cm` is running. Peer ids are empty when the window is closed or the title is not a peer id.
    case connected([String])
}

/// Session presence is the Connection Manager process. The peer id is its window title.
enum RustDeskSessionReader {
    static func read() async -> RustDeskConnection {
        let candidates = await MainActor.run { runningCandidates() }
        if candidates.isEmpty { return .absent }
        var managers: [pid_t] = []
        var unreadable = false
        for candidate in candidates {
            guard let arguments = ProcessArguments.arguments(pid: candidate.pid) else {
                unreadable = true
                continue
            }
            if RustDeskProcess.isConnectionManager(executable: candidate.executable, arguments: arguments) {
                managers.append(candidate.pid)
            }
        }
        if !managers.isEmpty {
            // Minimized CM windows stay in the AX window list, so their titles are read here.
            // A closed window yields no title; the probe keeps the session cache until `--cm` exits.
            return .connected(RustDeskWindowTitles.peerIDs(pids: managers))
        }
        return unreadable ? .unknown : .idle
    }

    @MainActor
    private static func runningCandidates() -> [ProcessCandidate] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated else { return nil }
            let executable = app.executableURL?.path ?? ""
            let bundlePath = app.bundleURL?.path ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            let matches = bundleID.caseInsensitiveCompare(RustDeskProcess.bundleIdentifier) == .orderedSame
                || bundlePath.contains("/RustDesk.app")
                || RustDeskProcess.looksLikeRustDesk(executable)
            guard matches else { return nil }
            return ProcessCandidate(pid: app.processIdentifier, executable: executable.isEmpty ? bundlePath : executable)
        }
    }
}

struct ProcessCandidate: Sendable {
    var pid: pid_t
    var executable: String
}

enum ProcessArguments {
    static func arguments(pid: pid_t) -> [String]? {
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        let listed = name.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return sysctl(base, 3, nil, &size, nil, 0)
        }
        guard listed == 0, size > MemoryLayout<Int32>.size else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        let copied = name.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return data.withUnsafeMutableBytes { raw in
                guard let destination = raw.baseAddress else { return false }
                var length = size
                let rc = sysctl(base, 3, destination, &length, nil, 0)
                return rc == 0 && length > MemoryLayout<Int32>.size
            }
        }
        guard copied else { return nil }
        return ProcessArgumentBlob.arguments(in: data)
    }
}

enum RustDeskWindowTitles {
    static func peerIDs(pids: [pid_t]) -> [String] {
        guard AXIsProcessTrusted(), !pids.isEmpty else { return [] }
        var ids: [String] = []
        for pid in pids {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.5)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &raw) == .success,
                  let windows = raw as? [AXUIElement] else { continue }
            for window in windows {
                var titleRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                      let title = titleRef as? String,
                      let id = RustDeskWindowTitle.peerID(in: title) else { continue }
                ids.append(id)
            }
        }
        return ids
    }
}
