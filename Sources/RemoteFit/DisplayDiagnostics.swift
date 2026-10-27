import AppKit
import RemoteFitCore

/// Geometry only: no screen pixels, window titles, typed input, or clipboard data.
@MainActor
enum DisplayDiagnostics {
    static func appKitGeometry() -> String {
        let screens = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return "id=\(id) frame=\(NSStringFromRect(screen.frame)) visible=\(NSStringFromRect(screen.visibleFrame)) scale=\(screen.backingScaleFactor)"
        }
        return "uptime=\(ProcessInfo.processInfo.systemUptime) primary=\((NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) screens=[\(screens.joined(separator: "; "))]"
    }
}

extension DisplayEngine {
    /// A fresh worker snapshot distinguishes system geometry from the UI process's AppKit view.
    /// Read-only and bounded; errors are diagnostic evidence, never an apply/restore failure.
    func recordDisplayObservation(expected: Dimensions, sequence: Int, reason: String,
                                  elapsed: Double, appKit: String, connection: String) {
        guard !Task.isCancelled, !shuttingDown, applied == expected else { return }
        do {
            let live = try snapshot()
            guard !Task.isCancelled else { return }
            let state = String(decoding: try encoder.encode(live), as: UTF8.self)
            log("display_observation", "sequence=\(sequence) reason=\(reason) elapsed=\(String(format: "%.3f", elapsed)) expected=\(expected.label) worker_uptime=\(ProcessInfo.processInfo.systemUptime) \(connection) cg=\(state) appkit={\(appKit)}")
        } catch {
            if !Task.isCancelled { log("display_observation_failed", "sequence=\(sequence) reason=\(reason) error=\(error.localizedDescription)") }
        }
    }
}
