import Foundation

/// One online display as CoreGraphics reported it, including panels the mode-based
/// snapshot drops. A mirrored panel often has no current mode, and on some systems it
/// is missing from CGGetOnlineDisplayList while still scanning out the virtual framebuffer.
public struct DisplaySample: Codable, Equatable, Sendable {
    public var id: UInt32
    public var uuid: String?
    public var hardwareKey: String
    public var ownVirtual: Bool
    public var main: Bool
    public var x: Int32
    public var y: Int32
    public var mirror: UInt32
    public var mode: DisplayMode?
    /// False when the id answered CGDisplayIsOnline but was absent from CGGetOnlineDisplayList.
    public var listedOnline: Bool

    public init(id: UInt32, uuid: String?, hardwareKey: String, ownVirtual: Bool, main: Bool,
                x: Int32, y: Int32, mirror: UInt32, mode: DisplayMode?, listedOnline: Bool) {
        self.id = id; self.uuid = uuid; self.hardwareKey = hardwareKey; self.ownVirtual = ownVirtual
        self.main = main; self.x = x; self.y = y; self.mirror = mirror; self.mode = mode
        self.listedOnline = listedOnline
    }
}

public enum DisplayCensus {
    /// Vendor 0 and no other evidence is a stale id from the bounded probe, not a panel.
    public static func isUsable(_ sample: DisplaySample) -> Bool {
        if sample.listedOnline || sample.ownVirtual || sample.mirror != 0 || sample.mode != nil { return true }
        return !sample.hardwareKey.hasPrefix("0:")
    }

    /// Physical panels stay in the set when they have no mode. Restore matches them by
    /// UUID / hardware key and writes the saved mode back; the zero placeholder is not applied.
    public static func states(from samples: [DisplaySample]) -> [DisplayState] {
        var seen = Set<UInt32>()
        return samples.compactMap { sample in
            guard isUsable(sample), seen.insert(sample.id).inserted else { return nil }
            var state = DisplayState(id: sample.id, uuid: sample.uuid, hardwareKey: sample.hardwareKey,
                                     physical: !sample.ownVirtual, main: sample.main,
                                     x: sample.x, y: sample.y, mirror: sample.mirror,
                                     mode: sample.mode ?? .init(width: 0, height: 0, pixelWidth: 0, pixelHeight: 0, refresh: 0))
            if sample.mode == nil { state.skipMode = true }
            return state
        }
    }

    public static func summary(_ samples: [DisplaySample]) -> String {
        let usable = samples.filter(isUsable)
        let physical = usable.filter { !$0.ownVirtual && !HeadlessPlaceholder.isPlaceholder(hardwareKey: $0.hardwareKey) }
        let modeless = physical.filter { $0.mode == nil }.count
        let unlisted = physical.filter { !$0.listedOnline }.count
        let parts = usable.map { sample in
            let mode = sample.mode.map { "\($0.pixelWidth)x\($0.pixelHeight)/\($0.width)x\($0.height)@\($0.refresh)" } ?? "mode=nil"
            return "id=\(sample.id) own=\(sample.ownVirtual) mirror=\(sample.mirror) listed=\(sample.listedOnline) \(mode) key=\(sample.hardwareKey) uuid=\(sample.uuid ?? "-")"
        }
        return "physical=\(physical.count) modeless=\(modeless) unlisted=\(unlisted) [\(parts.joined(separator: "; "))]"
    }
}

/// The mode a failed replacement should put back. The live snapshot often reports refresh 0
/// for a virtual display that is still showing the previous size; that must not fail the rollback.
/// Session snapshots taken while the panel was already hidden have nothing to map.
/// The last quiet physical layout is still the user's native desktop.
public enum NativeLayoutFallback {
    public static func targets(live: [DisplayState], stable: StableModes) -> [DisplayState]? {
        let physical = live.filter { $0.physical && !HeadlessPlaceholder.isPlaceholder($0) }
        guard !physical.isEmpty, stable.layouts[StableModes.setKey(physical)] != nil else { return nil }
        let corrected = stable.corrected(physical).states
        return corrected.map { state in
            var target = state
            target.mirror = 0
            target.main = state.main
            target.skipMode = false
            target.skipOrigin = false
            return target
        }
    }
}

public enum RollbackMode {
    public static func compatible(_ mode: DisplayMode, dimensions: Dimensions) -> Bool {
        VirtualDisplayReadiness.isCompatible(mode, dimensions: dimensions, scale: 2)
            || VirtualDisplayReadiness.isCompatible(mode, dimensions: dimensions, scale: 1)
    }

    /// Prefer the mode we successfully applied. Otherwise accept the live desktop size
    /// with an unspecified refresh filled in as 60 Hz. Nil lets the transition synthesize HiDPI.
    public static func selected(applied: DisplayMode?, live: DisplayMode, dimensions: Dimensions) -> DisplayMode? {
        if let applied, compatible(applied, dimensions: dimensions) { return applied }
        var live = live
        if live.refresh <= 0 { live.refresh = 60 }
        return compatible(live, dimensions: dimensions) ? live : nil
    }
}
