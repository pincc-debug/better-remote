import Foundation

public enum DisplayReconfiguration {
    /// Only the owned mirror source may change modes; never change the desktop topology.
    public static func target(in live: [DisplayState], sourceID: UInt32, dimensions: Dimensions) throws -> DisplayState {
        guard CustomPreset.isSupported(dimensions),
              var source = live.first(where: { $0.id == sourceID }), !source.physical,
              source.main, source.mirror == 0,
              live.filter({ $0.id != sourceID }).allSatisfy({ $0.physical && ($0.mirror == sourceID || $0.mirror == 0) }),
              live.contains(where: { $0.mirror == sourceID }) || !live.contains(where: \.physical) else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        source.mode = .init(width: dimensions.width, height: dimensions.height,
                            pixelWidth: dimensions.width * 2, pixelHeight: dimensions.height * 2, refresh: 60)
        source.skipMode = false
        source.skipOrigin = true
        return source
    }

    public static func sameTopology(_ live: [DisplayState], as baseline: [DisplayState]) -> Bool {
        guard live.count == baseline.count, Set(live.map(\.id)).count == live.count else { return false }
        return baseline.allSatisfy { before in
            guard let after = live.first(where: { $0.id == before.id }) else { return false }
            return after.uuid == before.uuid && after.physical == before.physical &&
                after.hardwareKey == before.hardwareKey && after.main == before.main &&
                after.mirror == before.mirror && after.x == before.x && after.y == before.y
        }
    }

    public static func matches(_ live: [DisplayState], baseline: [DisplayState], target: DisplayState) -> Bool {
        sameTopology(live, as: baseline) && live.first(where: { $0.id == target.id })?.mode.matches(target.mode) == true
    }
}
