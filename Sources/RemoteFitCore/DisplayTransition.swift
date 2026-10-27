import Foundation

public enum DisplayTransition {
    /// Hand mirrors (if any; a headless Mac has none) to a fresh source to a fresh source while keeping the previous source alive for rollback.
    public static func targets(source: DisplayState, dimensions: Dimensions,
                               physical: [DisplayState], retiring: DisplayState? = nil, selectedMode: DisplayMode? = nil) throws -> [DisplayState] {
        let ids = physical.map(\.id) + [source.id] + (retiring.map { [$0.id] } ?? [])
        guard CustomPreset.isSupported(dimensions), !source.physical, source.mirror == 0,
              Set(ids).count == ids.count,
              retiring.map({ !$0.physical && $0.mirror == 0 }) ?? true,
              physical.allSatisfy({ s in s.physical && (s.mirror == 0 || s.mirror == source.id || s.mirror == retiring?.id || physical.contains { $0.id == s.mirror }) }) else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        var next = source
        next.main = true; next.x = 0; next.y = 0; next.mirror = 0
        next.skipMode = false; next.skipOrigin = false
        next.mode = selectedMode ?? .init(width: dimensions.width, height: dimensions.height,
                          pixelWidth: dimensions.width * 2, pixelHeight: dimensions.height * 2, refresh: 60)
        guard VirtualDisplayReadiness.isCompatible(next.mode, dimensions: dimensions, scale: 2) ||
              VirtualDisplayReadiness.isCompatible(next.mode, dimensions: dimensions, scale: 1) else {
            throw FitError.message("目标显示模式与规格不符。")
        }
        var targets: [DisplayState] = []
        if var old = retiring {
            // Demote the old main display into the new mirror set. Keeping it as
            // an independent desktop can make WindowServer retain it as main.
            old.main = false; old.mirror = source.id
            old.skipMode = true; old.skipOrigin = true
            targets.append(old)
        }
        targets.append(next)
        // Every physical display mirrors the virtual source; its own mode/origin are not
        // required during the session and come back exactly on restore.
        targets += physical.map { state in
            var target = state
            target.main = false; target.mirror = source.id
            target.skipMode = true; target.skipOrigin = true
            return target
        }
        return targets
    }

    public static func matches(_ live: [DisplayState], targets: [DisplayState], sourceID: UInt32) -> Bool {
        guard live.count == targets.count, Set(live.map(\.id)).count == live.count,
              Set(live.map(\.id)) == Set(targets.map(\.id)),
              let source = live.first(where: { $0.id == sourceID }), !source.physical,
              source.main, source.mirror == 0, source.x == 0, source.y == 0 else { return false }
        return targets.allSatisfy { target in
            guard let actual = live.first(where: { $0.id == target.id }),
                  actual.uuid == target.uuid, actual.hardwareKey == target.hardwareKey,
                  actual.physical == target.physical, actual.main == target.main,
                  actual.mirror == target.mirror else { return false }
            if target.physical {
                if target.mirror == 0 { return actual.mirror == 0 && actual.mode.matches(target.mode) }
                return actual.mirror == sourceID
            }
            return (target.skipOrigin || (actual.x == target.x && actual.y == target.y)) &&
                (target.skipMode || actual.mode.matches(target.mode))
        }
    }
}
