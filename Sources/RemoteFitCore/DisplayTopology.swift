import Foundation

/// Locked copy for the resolution setting. Default behavior stays mirror-all.
public enum MultiDisplayExtendCopy {
    public static let title = "多屏保持扩展"
    public static let footnote = "开启后各屏同尺寸、互不镜像。远程通常只能看到其中一块。"
}

/// How a virtual-resolution session lays out more than one screen.
public enum DisplayTopology: String, Codable, Equatable, Sendable {
    /// One virtual source is main. Every physical display mirrors it, so each panel shows the same picture.
    case mirrorAll
    /// Each screen is its own desktop at the target size, arranged from the pre-session layout.
    case extended
}

extension DisplayTopology {
    /// A virtual framebuffer to create. `physicalID` is the panel it stands in for; nil when there is no panel
    /// (headless) or when every panel shares the single mirror-all source.
    public struct Slot: Equatable, Sendable {
        public var physicalID: UInt32?
        public var main: Bool
        public var x: Int32
        public var y: Int32
        public init(physicalID: UInt32?, main: Bool, x: Int32, y: Int32) {
            self.physicalID = physicalID
            self.main = main
            self.x = x
            self.y = y
        }
    }

    public static func slots(topology: DisplayTopology, physical: [DisplayState], dimensions: Dimensions) -> [Slot] {
        switch topology {
        case .mirrorAll:
            return [Slot(physicalID: nil, main: true, x: 0, y: 0)]
        case .extended:
            guard !physical.isEmpty else { return [Slot(physicalID: nil, main: true, x: 0, y: 0)] }
            return ExtendedArrangement.place(physical, size: dimensions).map {
                Slot(physicalID: $0.id, main: $0.main, x: $0.x, y: $0.y)
            }
        }
    }

    /// Commit plan. Mirror-all delegates to `DisplayTransition` so today's single-source path stays unchanged.
    /// Extended builds one virtual framebuffer per physical display. Those framebuffers are unmirrored, share the
    /// requested mode, and keep the pre-session arrangement (pushed apart only when the new size would overlap).
    /// Each physical panel is bound to its own framebuffer. A panel cannot switch to an arbitrary virtual size —
    /// that mode is not in its list — so the binding is what makes the panel show that desktop. Panels do not
    /// share one source, so the desktops are not clones. Headless (no physical display) stays a single framebuffer.
    public static func targets(topology: DisplayTopology, sources: [DisplayState], modes: [DisplayMode],
                               dimensions: Dimensions, physical: [DisplayState],
                               retiring: [DisplayState] = []) throws -> [DisplayState] {
        switch topology {
        case .mirrorAll:
            guard sources.count == 1, modes.count == 1, sources[0].mirror == 0, !sources[0].physical else {
                throw FitError.message("显示器布局已变化，请先还原屏幕")
            }
            if retiring.count <= 1 {
                return try DisplayTransition.targets(source: sources[0], dimensions: dimensions, physical: physical,
                                                     retiring: retiring.first, selectedMode: modes[0])
            }
            guard retiring.allSatisfy({ !$0.physical && $0.mirror == 0 }) else {
                throw FitError.message("显示器布局已变化，请先还原屏幕")
            }
            let base = try DisplayTransition.targets(source: sources[0], dimensions: dimensions, physical: physical,
                                                     selectedMode: modes[0])
            let mainID = sources[0].id
            let demoted = retiring.map { old -> DisplayState in
                var old = old
                old.main = false
                old.mirror = mainID
                old.skipMode = true
                old.skipOrigin = true
                return old
            }
            let ids = demoted.map(\.id) + base.map(\.id)
            guard Set(ids).count == ids.count else { throw FitError.message("显示器布局已变化，请先还原屏幕") }
            return demoted + base
        case .extended:
            return try extendedTargets(sources: sources, modes: modes, dimensions: dimensions,
                                       physical: physical, retiring: retiring)
        }
    }

    /// Resolve virtual displays after several have been created. macOS can reassign display IDs
    /// when the next framebuffer appears; UUIDs stay put. Committing the IDs captured before that
    /// reassignment fails and the activation restores the previous desktop.
    public static func rebound(_ sources: [DisplayState], live: [DisplayState]) -> [DisplayState]? {
        var used = Set<UInt32>()
        var resolved: [DisplayState] = []
        for source in sources {
            guard let match = live.first(where: { candidate in
                guard !candidate.physical, !used.contains(candidate.id) else { return false }
                if let uuid = source.uuid { return candidate.uuid == uuid }
                return candidate.id == source.id
            }) else { return nil }
            used.insert(match.id)
            resolved.append(match)
        }
        return resolved
    }

    /// `sourceID` is the planned main virtual framebuffer. Retiring framebuffers may mirror it.
    /// Live desktops are not clones of one another. macOS may translate the whole arrangement;
    /// that must not look like a failed switch. A collapsed stack, or every panel mirroring one
    /// framebuffer, is not the extended plan.
    public static func matches(_ live: [DisplayState], targets: [DisplayState], sourceID: UInt32) -> Bool {
        guard live.count == targets.count, Set(live.map(\.id)).count == live.count,
              Set(live.map(\.id)) == Set(targets.map(\.id)),
              let source = live.first(where: { $0.id == sourceID }), !source.physical,
              source.mirror == 0 else { return false }
        let desktops = targets.filter { !$0.physical && $0.mirror == 0 }
        let desktopIDs = Set(desktops.map(\.id))
        let mains = live.filter(\.main)
        guard mains.count == 1, let main = mains.first, desktopIDs.contains(main.id) else { return false }
        guard extendedLayoutHolds(live: live, planned: desktops) else { return false }
        let virtualIDs = Set(targets.filter { !$0.physical }.map(\.id))
        return targets.allSatisfy { target in
            guard let actual = live.first(where: { $0.id == target.id }),
                  actual.uuid == target.uuid, actual.hardwareKey == target.hardwareKey,
                  actual.physical == target.physical, actual.mirror == target.mirror else { return false }
            if target.physical {
                if target.mirror == 0 {
                    let modeOK = target.skipMode || actual.mode.matches(target.mode)
                    let originOK = target.skipOrigin || (actual.x == target.x && actual.y == target.y)
                    return modeOK && originOK
                }
                return virtualIDs.contains(target.mirror)
            }
            if target.mirror != 0 { return target.mirror == sourceID && !target.main }
            let modeOK = target.skipMode || actual.mode.matches(target.mode)
            if target.main { return modeOK && desktopIDs.contains(target.id) }
            return modeOK
        }
    }

    /// Relative placement of the unmirrored desktops, allowing one translation of the whole set.
    private static func extendedLayoutHolds(live: [DisplayState], planned: [DisplayState]) -> Bool {
        guard let plannedMain = planned.first(where: \.main),
              let liveMain = live.first(where: { $0.id == plannedMain.id }) else { return false }
        let dx = Int(liveMain.x) - Int(plannedMain.x)
        let dy = Int(liveMain.y) - Int(plannedMain.y)
        var livePoints = Set<String>()
        for item in planned {
            guard let actual = live.first(where: { $0.id == item.id }) else { return false }
            if Int(actual.x) - Int(item.x) != dx || Int(actual.y) - Int(item.y) != dy { return false }
            livePoints.insert("\(actual.x),\(actual.y)")
        }
        return livePoints.count == Set(planned.map { "\($0.x),\($0.y)" }).count
    }

    private static func extendedTargets(sources: [DisplayState], modes: [DisplayMode], dimensions: Dimensions,
                                        physical: [DisplayState], retiring: [DisplayState]) throws -> [DisplayState] {
        let slots = slots(topology: .extended, physical: physical, dimensions: dimensions)
        let ids = sources.map(\.id) + physical.map(\.id) + retiring.map(\.id)
        guard CustomPreset.isSupported(dimensions),
              sources.count == slots.count, modes.count == slots.count,
              Set(ids).count == ids.count,
              Set(physical.map(\.id)).count == physical.count,
              sources.allSatisfy { !$0.physical },
              physical.allSatisfy(\.physical),
              retiring.allSatisfy({ !$0.physical }) else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        var virtuals: [DisplayState] = []
        for (index, slot) in slots.enumerated() {
            var next = sources[index]
            next.main = slot.main
            next.x = slot.x
            next.y = slot.y
            next.mirror = 0
            next.skipMode = false
            next.skipOrigin = false
            next.mode = modes[index]
            guard VirtualDisplayReadiness.isCompatible(next.mode, dimensions: dimensions, scale: 2) ||
                    VirtualDisplayReadiness.isCompatible(next.mode, dimensions: dimensions, scale: 1) else {
                throw FitError.message("目标显示模式与规格不符。")
            }
            virtuals.append(next)
        }
        guard virtuals.filter(\.main).count == 1, let main = virtuals.first(where: \.main),
              main.x == 0, main.y == 0 else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        var targets: [DisplayState] = retiring.map { old in
            var old = old
            old.main = false
            old.mirror = main.id
            old.skipMode = true
            old.skipOrigin = true
            return old
        }
        targets += virtuals
        guard !physical.isEmpty else {
            guard slots.count == 1, slots[0].physicalID == nil else {
                throw FitError.message("显示器布局已变化，请先还原屏幕")
            }
            return targets
        }
        var framebuffer: [UInt32: UInt32] = [:]
        for (index, slot) in slots.enumerated() {
            guard let physicalID = slot.physicalID, framebuffer[physicalID] == nil else {
                throw FitError.message("显示器布局已变化，请先还原屏幕")
            }
            framebuffer[physicalID] = sources[index].id
        }
        guard framebuffer.count == physical.count else { throw FitError.message("显示器布局已变化，请先还原屏幕") }
        for state in physical {
            var target = state
            target.main = false
            guard let master = framebuffer[state.id] else { throw FitError.message("显示器布局已变化，请先还原屏幕") }
            target.mirror = master
            target.skipMode = true
            target.skipOrigin = true
            targets.append(target)
        }
        guard targets.filter(\.physical).allSatisfy({ $0.mirror != 0 }),
              Set(targets.filter(\.physical).map(\.mirror)).count == physical.count else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        return targets
    }
}

/// Same-size rectangles that keep the pre-session relative order and do not overlap.
/// The original main display (else the bottom-most, then left-most) stays main and moves to (0, 0).
public enum ExtendedArrangement {
    public struct Placement: Equatable, Sendable {
        public var id: UInt32
        public var main: Bool
        public var x: Int32
        public var y: Int32
        public init(id: UInt32, main: Bool, x: Int32, y: Int32) {
            self.id = id
            self.main = main
            self.x = x
            self.y = y
        }
    }

    public static func place(_ displays: [DisplayState], size: Dimensions) -> [Placement] {
        guard !displays.isEmpty else { return [] }
        let anchorIndex = displays.firstIndex(where: \.main) ?? displays.indices.min { lhs, rhs in
            let a = displays[lhs], b = displays[rhs]
            if a.y != b.y { return a.y < b.y }
            if a.x != b.x { return a.x < b.x }
            return a.id < b.id
        }!
        let anchor = displays[anchorIndex]
        struct Rect {
            var id: UInt32
            var x: Int
            var y: Int
            var main: Bool
            var centerX: Int
            var centerY: Int
        }
        let width = max(1, size.width)
        let height = max(1, size.height)
        var rects: [Rect] = displays.map { display in
            Rect(id: display.id,
                 x: Int(display.x) - Int(anchor.x),
                 y: Int(display.y) - Int(anchor.y),
                 main: display.id == anchor.id,
                 centerX: Int(display.x) + display.mode.width / 2,
                 centerY: Int(display.y) + display.mode.height / 2)
        }
        func overlap(_ a: Rect, _ b: Rect) -> (Int, Int)? {
            let ox = min(a.x + width, b.x + width) - max(a.x, b.x)
            let oy = min(a.y + height, b.y + height) - max(a.y, b.y)
            guard ox > 0, oy > 0 else { return nil }
            return (ox, oy)
        }
        let limit = max(8, rects.count * rects.count)
        for _ in 0..<limit {
            var moved = false
            for i in rects.indices {
                for j in rects.indices where i < j {
                    guard let (ox, oy) = overlap(rects[i], rects[j]) else { continue }
                    let dx = rects[j].centerX - rects[i].centerX
                    let dy = rects[j].centerY - rects[i].centerY
                    if dx == 0, dy == 0 {
                        if rects[j].id >= rects[i].id { rects[j].x += ox } else { rects[i].x += ox }
                    } else if abs(dx) >= abs(dy) {
                        if dx > 0 || (dx == 0 && rects[j].id >= rects[i].id) { rects[j].x += ox } else { rects[i].x += ox }
                    } else if dy > 0 || (dy == 0 && rects[j].id >= rects[i].id) {
                        rects[j].y += oy
                    } else {
                        rects[i].y += oy
                    }
                    moved = true
                }
            }
            if !moved { break }
        }
        guard let pinned = rects.first(where: \.main) else { return [] }
        return rects.map { rect in
            Placement(id: rect.id, main: rect.main,
                      x: Int32(clamping: rect.x - pinned.x),
                      y: Int32(clamping: rect.y - pinned.y))
        }.sorted { lhs, rhs in
            if lhs.main != rhs.main { return lhs.main }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.id < rhs.id
        }
    }
}
