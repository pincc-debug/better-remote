import Foundation

public struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Original UU label used for matching; never edited by the display-name field.
    public var name: String
    public var customName: String?
    public var isNew: Bool?
    public var displayName: String {
        let value = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? name : value
    }
    /// Missing in older files means enabled; keep inheritance separate from activation.
    public var configurationEnabled: Bool?
    public var appliesConfiguration: Bool { configurationEnabled != false }
    public var configuration: DeviceConfiguration?
    public var presetID: String?
    public init(id: String, name: String, presetID: String? = nil, configuration: DeviceConfiguration? = nil, configurationEnabled: Bool? = nil, customName: String? = nil, isNew: Bool? = nil) {
        self.id = id; self.name = name; self.customName = customName; self.isNew = isNew; self.presetID = presetID; self.configuration = configuration; self.configurationEnabled = configurationEnabled
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
                remoteDevices[index] = .init(id: device.id, name: device.name, presetID: remoteDevices[index].presetID, configuration: remoteDevices[index].configuration, configurationEnabled: remoteDevices[index].configurationEnabled, customName: remoteDevices[index].customName, isNew: remoteDevices[index].isNew)
            } else {
                remoteDevices.append(.init(id: device.id, name: device.name, configuration: DeviceConfiguration(preferences: self), isNew: true))
            }
        }
    }

    public func automaticPreset(for deviceID: String?) -> CustomPreset? {
        guard appliesConfiguration(for: deviceID) else { return nil }
        if let deviceID, let configuration = remoteDevices.first(where: { $0.id == deviceID })?.configuration {
            return configuration.autoResolutionEnabled ? customPresets.first { $0.id == configuration.autoResolutionPresetID } : nil
        }
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
    public mutating func remove(_ id: String, from preferences: inout Preferences, suppressRediscovery: Bool = true) {
        if suppressRediscovery { removed.insert(id) } else { removed.remove(id) }
        preferences.remoteDevices.removeAll { $0.id == id }
    }
    public func remember(_ device: RemoteDevice, in preferences: inout Preferences) {
        guard !removed.contains(device.id) else { return }
        preferences.remember(device)
    }
    public func isRemoved(_ id: String?) -> Bool { id.map { removed.contains($0) } ?? false }
    public mutating func disconnected() { removed.removeAll() }
}

/// Each device owns a snapshot. Nil is accepted only for legacy data migration.
public struct DeviceConfiguration: Codable, Equatable, Sendable {
    public var autoResolutionEnabled: Bool
    public var autoResolutionPresetID: String?
    public var autoRestoreOnDisconnect: Bool
    public var uuTouchScrollEnabled: Bool
    public var uuScrollSpeedPercent: Int
    public var autoFillWindowsOnRemote: Bool
    public var connectionDockMode: ConnectionDockMode
    public var toolbarWhenConnected: Bool
    public var toolbarSide: ToolbarSide

    public init(preferences: Preferences) {
        autoResolutionEnabled = preferences.autoResolutionEnabled && preferences.defaultResolutionEnabled
        autoResolutionPresetID = preferences.autoResolutionPresetID
        autoRestoreOnDisconnect = preferences.autoRestoreOnDisconnect
        uuTouchScrollEnabled = preferences.uuTouchScrollEnabled
        uuScrollSpeedPercent = preferences.uuScrollSpeedPercent
        autoFillWindowsOnRemote = preferences.autoFillWindowsOnRemote
        connectionDockMode = preferences.connectionDockMode
        toolbarWhenConnected = preferences.toolbarWhenConnected
        toolbarSide = preferences.toolbarSide
    }

    public func applying(to preferences: Preferences) -> Preferences {
        var result = preferences
        result.autoResolutionEnabled = autoResolutionEnabled
        result.defaultResolutionEnabled = true
        result.autoResolutionPresetID = autoResolutionPresetID
        result.autoRestoreOnDisconnect = autoRestoreOnDisconnect
        result.uuTouchScrollEnabled = uuTouchScrollEnabled
        result.uuScrollSpeedPercent = UUScrollScaling.clampedPercent(uuScrollSpeedPercent)
        result.autoFillWindowsOnRemote = autoFillWindowsOnRemote
        result.connectionDockMode = connectionDockMode
        result.toolbarWhenConnected = toolbarWhenConnected
        result.toolbarSide = toolbarSide
        return result
    }
}

extension Preferences {
    public func configuration(for deviceID: String?) -> DeviceConfiguration {
        if let deviceID, let device = remoteDevices.first(where: { $0.id == deviceID }) {
            if let configuration = device.configuration { return configuration }
            if deviceResolutionEnabled, let presetID = device.presetID {
                var configuration = DeviceConfiguration(preferences: self)
                configuration.autoResolutionEnabled = autoResolutionEnabled
                configuration.autoResolutionPresetID = presetID
                return configuration
            }
        }
        return DeviceConfiguration(preferences: self)
    }

    public mutating func setConfiguration(_ configuration: DeviceConfiguration, for deviceID: String?) {
        if let deviceID {
            guard let index = remoteDevices.firstIndex(where: { $0.id == deviceID }) else { return }
            remoteDevices[index].configuration = configuration
            remoteDevices[index].presetID = nil
        } else {
            self = configuration.applying(to: self)
        }
    }

    public mutating func migrateDeviceConfigurations() {
        for index in remoteDevices.indices where remoteDevices[index].configuration == nil {
            var configuration: DeviceConfiguration
            if let presetID = remoteDevices[index].presetID {
                configuration = DeviceConfiguration(preferences: Preferences())
                configuration.autoResolutionEnabled = autoResolutionEnabled && deviceResolutionEnabled
                configuration.autoResolutionPresetID = presetID
            } else {
                configuration = DeviceConfiguration(preferences: self)
            }
            remoteDevices[index].configuration = configuration
            remoteDevices[index].presetID = nil
        }
    }
}

extension Preferences {
    public func appliesConfiguration(for deviceID: String?) -> Bool {
        guard let deviceID else { return true }
        return remoteDevices.first { $0.id == deviceID }?.appliesConfiguration ?? true
    }

    /// Runtime-only bypass. The saved defaults and independent profile remain untouched.
    public func effectiveConfiguration(for deviceID: String?) -> DeviceConfiguration {
        guard !appliesConfiguration(for: deviceID) else {
            var result = configuration(for: deviceID)
            // With no resolution selected, disconnect must not restore the screen either.
            result.autoResolutionEnabled = result.autoResolutionEnabled && customPresets.contains { $0.id == result.autoResolutionPresetID }
            result.autoRestoreOnDisconnect = result.autoResolutionEnabled && result.autoRestoreOnDisconnect
            return result
        }
        return bypassedConfiguration
    }

    public var bypassedConfiguration: DeviceConfiguration {
        var result = DeviceConfiguration(preferences: self)
        result.autoResolutionEnabled = false
        result.autoRestoreOnDisconnect = false
        result.uuTouchScrollEnabled = false
        result.uuScrollSpeedPercent = 100
        result.autoFillWindowsOnRemote = false
        result.connectionDockMode = .keep
        result.toolbarWhenConnected = toolbarWhenDisconnected
        return result
    }
}

extension Preferences {
    public mutating func renameDevice(_ deviceID: String, to name: String) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteDevices[index].customName = trimmed.isEmpty || trimmed == remoteDevices[index].name ? nil : String(trimmed.prefix(128))
    }
}

extension DeviceConfiguration {
    public var selectedResolutionID: String? { autoResolutionEnabled ? autoResolutionPresetID : nil }
    public mutating func selectResolution(_ id: String?) {
        autoResolutionPresetID = id
        autoResolutionEnabled = id != nil
    }
}
