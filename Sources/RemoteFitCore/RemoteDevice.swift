import Foundation

public struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var presetID: String?
    public init(id: String, name: String, presetID: String? = nil) {
        self.id = id; self.name = name; self.presetID = presetID
    }
}

/// Window-based identity uses the exact displayed controller name. No cached
/// device list is imported; only an active control row can create a profile.
public enum UUWindowDeviceParser {
    public static func device(in row: [String]) -> RemoteDevice? {
        let texts = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let controlIndex = texts.firstIndex(where: { $0 == "远程控制" || $0.contains(" 远程控制") }) else { return nil }
        let controlText = texts[controlIndex]
        let name: String?
        if let range = controlText.range(of: " 远程控制") {
            name = String(controlText[..<range.lowerBound])
        } else {
            name = texts.prefix(controlIndex).first { !$0.hasPrefix("连接时长") }
        }
        guard let name, !name.isEmpty, name.count <= 256, !name.contains("本机被控中") else { return nil }
        return RemoteDevice(id: "uu:window:" + name, name: name)
    }
}

extension Preferences {
    public mutating func remember(_ device: RemoteDevice) {
        if let index = remoteDevices.firstIndex(where: { $0.id == device.id }) {
            remoteDevices[index].name = device.name
        } else {
            let legacyMatches = remoteDevices.indices.filter {
                remoteDevices[$0].name == device.name && !remoteDevices[$0].id.hasPrefix("uu:window:")
            }
            if device.id.hasPrefix("uu:window:"), legacyMatches.count == 1, let index = legacyMatches.first {
                remoteDevices[index] = .init(id: device.id, name: device.name, presetID: remoteDevices[index].presetID)
            } else {
                remoteDevices.append(.init(id: device.id, name: device.name))
            }
        }
    }

    public func automaticPreset(for deviceID: String?) -> CustomPreset? {
        if deviceResolutionEnabled, let deviceID, let id = remoteDevices.first(where: { $0.id == deviceID })?.presetID,
           let preset = customPresets.first(where: { $0.id == id }) { return preset }
        return defaultResolutionEnabled ? customPresets.first { $0.id == autoResolutionPresetID } : nil
    }
}

/// A manual removal lasts through the current connection. It must not be undone
/// by the next detector sample; a later connection may discover the device anew.
public struct RemoteDeviceCollection: Sendable {
    private var removed = Set<String>()
    public init() {}
    public mutating func remove(_ id: String, from preferences: inout Preferences) {
        removed.insert(id)
        preferences.remoteDevices.removeAll { $0.id == id }
    }
    public func remember(_ device: RemoteDevice, in preferences: inout Preferences) {
        guard !removed.contains(device.id) else { return }
        preferences.remember(device)
    }
    public mutating func disconnected() { removed.removeAll() }
}
