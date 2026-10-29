import Foundation

/// Stable device-id prefixes. UU and RustDesk stay distinct even for one phone.
public enum RemoteDeviceKey {
    public static func uuWindow(_ name: String) -> String { "uu:window:" + name }
    public static func rustDesk(peerID: String) -> String { "rustdesk:id:" + peerID }
}

public enum RemoteDeviceIdentity {
    public static func rustDesk(peerID: String) -> RemoteDevice {
        RemoteDevice(id: RemoteDeviceKey.rustDesk(peerID: peerID), name: peerID)
    }
}

/// Connection Manager window title `{peerId} - RustDesk`, for example `1283940661 - RustDesk`.
/// Only a decimal peer id is a device key. A source address is not.
public enum RustDeskWindowTitle {
    public static func peerID(in title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: " - ") else { return nil }
        let id = trimmed[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmed[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix == "RustDesk", isPeerID(id) else { return nil }
        return id
    }

    public static func isPeerID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 32 && id.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }
}

public enum RustDeskProcess {
    /// Installed client. Path matching still accepts `RustDesk.app` if the id differs in case.
    public static let bundleIdentifier = "com.carriez.rustdesk"

    public static func looksLikeRustDesk(_ path: String) -> Bool {
        path.contains("/RustDesk.app/") || path.hasSuffix("/RustDesk.app")
            || path.hasSuffix("/RustDesk") || path.hasSuffix("/rustdesk")
    }

    /// The controlled-side session is the `RustDesk --cm` process, not the main window or `--server`.
    public static func isConnectionManager(executable: String, arguments: [String]) -> Bool {
        guard arguments.contains("--cm") else { return false }
        if looksLikeRustDesk(executable) { return true }
        return arguments.prefix(1).contains(where: looksLikeRustDesk)
    }
}

/// `KERN_PROCARGS2` layout: native argc, executable path, NUL padding, then argc C strings.
public enum ProcessArgumentBlob {
    public static func arguments(in buffer: [UInt8]) -> [String]? {
        let argcWidth = MemoryLayout<Int32>.size
        guard buffer.count >= argcWidth else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0, argc < 4096 else { return nil }
        var index = argcWidth
        guard skipCString(buffer, &index) else { return nil }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        arguments.reserveCapacity(argc)
        for _ in 0..<argc {
            let start = index
            guard skipCString(buffer, &index) else { return nil }
            let bytes = buffer[start..<(index - 1)]
            guard let string = String(bytes: bytes, encoding: .utf8) else { return nil }
            arguments.append(string)
        }
        return arguments
    }

    private static func skipCString(_ buffer: [UInt8], _ index: inout Int) -> Bool {
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        guard index < buffer.count else { return false }
        index += 1
        return true
    }
}

public struct RustDeskIdentitySample: Equatable, Sendable {
    /// Rows worth remembering. Empty when this session has no peer id yet.
    public var devices: [RemoteDevice]
    /// Set only when the session resolves to exactly one peer.
    public var sessionDevice: RemoteDevice?
    public init(devices: [RemoteDevice], sessionDevice: RemoteDevice?) {
        self.devices = devices
        self.sessionDevice = sessionDevice
    }
}

/// Last CM peer id for the current session. A closed window keeps it; disconnect clears it.
public struct RustDeskSessionIdentity: Equatable, Sendable {
    public private(set) var peerID: String?
    public init() {}

    public mutating func sample(sessionConnected: Bool, visiblePeerIDs: [String]) -> RustDeskIdentitySample {
        guard sessionConnected else {
            peerID = nil
            return RustDeskIdentitySample(devices: [], sessionDevice: nil)
        }
        var seen = Set<String>()
        var unique: [String] = []
        for id in visiblePeerIDs where RustDeskWindowTitle.isPeerID(id) && seen.insert(id).inserted {
            unique.append(id)
        }
        unique.sort()
        switch unique.count {
        case 0:
            guard let peerID else { return RustDeskIdentitySample(devices: [], sessionDevice: nil) }
            let device = RemoteDeviceIdentity.rustDesk(peerID: peerID)
            return RustDeskIdentitySample(devices: [device], sessionDevice: device)
        case 1:
            peerID = unique[0]
            let device = RemoteDeviceIdentity.rustDesk(peerID: unique[0])
            return RustDeskIdentitySample(devices: [device], sessionDevice: device)
        default:
            // More than one phone is on this session. Don't keep a single cached id.
            peerID = nil
            return RustDeskIdentitySample(
                devices: unique.map { RemoteDeviceIdentity.rustDesk(peerID: $0) },
                sessionDevice: nil
            )
        }
    }
}
