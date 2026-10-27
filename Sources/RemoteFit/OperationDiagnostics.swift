import AppKit

/// Records action metadata only; never captures typed text or clipboard contents.
enum OperationDiagnostics {
    /// Mouse metadata only. Event coordinates and the live cursor are separate:
    /// remote clients can deliver clicks without moving the system cursor.
    @MainActor
    static func mouseDetails(_ event: NSEvent, in view: NSView) -> String {
        let local = view.convert(event.locationInWindow, from: nil)
        let pointer = NSEvent.mouseLocation
        let cg = event.cgEvent
        let location = cg?.location ?? .zero
        let source = cg?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1
        let target = cg?.getIntegerValueField(.eventTargetUnixProcessID) ?? -1
        return "eventXY=\(event.locationInWindow) localXY=\(local) pointerXY=\(pointer) cgXY=\(location) sourcePID=\(source) targetPID=\(target) clicks=\(event.clickCount) eventTime=\(event.timestamp) frame=\(view.frame) windowFrame=\(view.window?.frame ?? .zero)"
    }

    private static let queue = DispatchQueue(label: "local.RemoteFit.operation-diagnostics", qos: .utility)
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteFit/Operations.log")

    static func write(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        queue.async {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
                try? Data().write(to: url, options: .atomic)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
