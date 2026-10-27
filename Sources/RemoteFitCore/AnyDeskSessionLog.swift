import Foundation

/// AnyDesk 9.8 macOS trace adapter. Service PID + fiber identifies a session;
/// backend PID alone does not (it can serve several accepted/pending requests).
public struct AnyDeskSessionLog: Sendable {
    public enum Status: Equatable, Sendable { case connected, disconnected, unknown }
    private struct Session: Sendable {
        var backend: Int32?
        var desktop = false
        var incoming = false
        var started: Date?
        var observed: Date?
        var closed = false
        var recovering = false
    }
    private var sessions: [String: Session] = [:]
    public init() {}

    public mutating func consume(_ line: String) {
        guard let separator = line.range(of: " - ") else { return }
        let header = line[..<separator.lowerBound].split(whereSeparator: \.isWhitespace)
        // level date time role thread pid tid fiber component
        guard header.count == 9, ["lsvc", "gsvc"].contains(header[3]),
              header[8] == "app.session", Int32(header[5]) != nil, Int(header[7]) != nil else { return }
        let message = line[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let relevant = message.hasPrefix("Session features:") || message.hasPrefix("Backend PID:") ||
            message.hasPrefix("Backend (retry) PID:") || message == "2: Requesting a session at the backend." ||
            message == "5: Entering processing loop." || message.hasPrefix("Session closed") ||
            message == "5: Processing done." || message == "Backend respawn succeeded." ||
            message == "Backend terminated." || message == "IPC socket closed unexpectedly."
        guard relevant else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let time = formatter.date(from: "\(header[1])T\(header[2])Z") else { return }
        let key = "\(header[5]):\(header[7])"
        var session = sessions[key] ?? Session()
        if message.hasPrefix("Session features:") {
            // Fibers may be reused; a new feature declaration starts a fresh request.
            session = Session()
            session.desktop = message.dropFirst("Session features:".count)
                .split { $0 == "," || $0 == "." || $0.isWhitespace }.contains("deskrt")
        } else if message.hasPrefix("Backend PID:") || message.hasPrefix("Backend (retry) PID:") {
            let next = message.split(separator: " ").last.flatMap { Int32($0) }
            if next != session.backend, session.started != nil, !session.closed { session.recovering = true }
            session.backend = next
        } else if message == "2: Requesting a session at the backend." {
            session.incoming = true
        } else if message == "5: Entering processing loop." || message == "Backend respawn succeeded." {
            // Observed only after authentication and 'Backend ready', alongside
            // backend 'Session started (ok)'. Pending/rejected requests never reach it.
            session.started = time
            session.recovering = false
        } else if message == "Backend terminated." || message == "IPC socket closed unexpectedly." {
            session.recovering = session.started != nil && !session.closed
        } else {
            session.closed = true
        }
        session.observed = time
        sessions[key] = session
    }

    /// Require a live assertion owner and its process birth time, so an old trace
    /// cannot resurrect a dead session or a reused PID after Better Remote restarts.
    public func status(backends: [Int32: Date]) -> Status {
        guard !backends.isEmpty else { return .disconnected }
        var known = Set<Int32>()
        var recovering = false
        for session in sessions.values {
            guard let pid = session.backend, let birth = backends[pid],
                  let observed = session.observed, observed >= birth.addingTimeInterval(-1) else { continue }
            known.insert(pid)
            if session.recovering, !session.closed { recovering = true; continue }
            if session.desktop, session.incoming, !session.closed,
               let started = session.started, started >= birth.addingTimeInterval(-1) { return .connected }
        }
        return !recovering && known.isSuperset(of: backends.keys) ? .disconnected : .unknown
    }

    public mutating func retain(backends: Set<Int32>) {
        // The new backend mapping can arrive before its power assertion. Keep
        // open sessions through that handoff, even if their PID is not yet live.
        sessions = sessions.filter { !$0.value.closed || ($0.value.backend.map(backends.contains) ?? true) }
        // Unbound requests can straddle reads, but unrelated/outgoing requests
        // must not accumulate indefinitely in a long-running client.
        let unbound = sessions.filter { $0.value.backend == nil }
            .sorted { ($0.value.observed ?? .distantPast) > ($1.value.observed ?? .distantPast) }
        for item in unbound.dropFirst(128) { sessions.removeValue(forKey: item.key) }
    }

}
