import Foundation

/// The last full physical layout (mode + origin + main + mirror per monitor) that held steadily
/// through a quiet window while no remote session or display operation was active, stored per
/// set of connected monitors. A change made by the remote tool or macOS right at connect time
/// is too short-lived to replace the user's real arrangement.
public struct StableModes: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var mode: DisplayMode
        public var x: Int32
        public var y: Int32
        public var main: Bool
        public var mirrorKey: String?
    }
    /// set key (sorted monitor keys) -> monitor key -> entry
    public var layouts: [String: [String: Entry]] = [:]
    public init() {}

    public static func key(_ state: DisplayState) -> String { state.uuid ?? state.hardwareKey }
    public static func setKey(_ states: [DisplayState]) -> String {
        states.filter(\.physical).map(key).sorted().joined(separator: "|")
    }
    static func entries(_ states: [DisplayState]) -> [String: Entry] {
        let byID = Dictionary(states.map { ($0.id, key($0)) }, uniquingKeysWith: { a, _ in a })
        return Dictionary(states.filter(\.physical).map {
            (key($0), Entry(mode: $0.mode, x: $0.x, y: $0.y, main: $0.main, mirrorKey: $0.mirror == 0 ? nil : byID[$0.mirror]))
        }, uniquingKeysWith: { a, _ in a })
    }
    static func same(_ a: Entry, _ b: Entry) -> Bool {
        a.mode.matches(b.mode) && a.x == b.x && a.y == b.y && a.main == b.main && a.mirrorKey == b.mirrorKey
    }
    static func same(_ a: [String: Entry], _ b: [String: Entry]) -> Bool {
        a.count == b.count && a.allSatisfy { k, v in b[k].map { same(v, $0) } ?? false }
    }

    /// Record the layout when it stayed identical from `baseline` (start of the quiet window)
    /// to `live` (its end). Returns true when the stored layout changed.
    @discardableResult
    public mutating func record(baseline: [DisplayState], live: [DisplayState]) -> Bool {
        guard !live.isEmpty, live.allSatisfy(\.physical), baseline.allSatisfy(\.physical) else { return false }
        let set = Self.setKey(live)
        guard Self.setKey(baseline) == set else { return false }
        let now = Self.entries(live)
        guard Self.same(Self.entries(baseline), now) else { return false }
        if let old = layouts[set], Self.same(old, now) { return false }
        layouts[set] = now
        return true
    }

    /// Replace the live layout by the stored one for the same monitor set when they differ.
    public func corrected(_ states: [DisplayState]) -> (states: [DisplayState], fixed: [UInt32]) {
        guard let stored = layouts[Self.setKey(states)], !Self.same(stored, Self.entries(states)) else { return (states, []) }
        let idByKey = Dictionary(states.map { (Self.key($0), $0.id) }, uniquingKeysWith: { a, _ in a })
        var fixed: [UInt32] = []
        let result = states.map { state -> DisplayState in
            guard state.physical, let e = stored[Self.key(state)] else { return state }
            var s = state
            s.mode = e.mode; s.x = e.x; s.y = e.y; s.main = e.main
            s.mirror = e.mirrorKey.flatMap { idByKey[$0] } ?? 0
            if !Self.same(e, Self.entries([state])[Self.key(state)]!) || s.mirror != state.mirror { fixed.append(state.id) }
            return s
        }
        return (result, fixed)
    }

    /// Field-level differences between a restore target and the live display (for logs).
    public static func mismatches(target: DisplayState, actual: DisplayState?) -> [String] {
        guard let a = actual else { return ["id \(target.id) missing"] }
        var out: [String] = []
        let t = target.mode, m = a.mode
        if !target.skipMode && !m.matches(t) { out.append("mode \(m.pixelWidth)x\(m.pixelHeight)/\(m.width)x\(m.height)@\(m.refresh) != \(t.pixelWidth)x\(t.pixelHeight)/\(t.width)x\(t.height)@\(t.refresh)") }
        if a.x != target.x || a.y != target.y { out.append("origin \(a.x),\(a.y) != \(target.x),\(target.y)") }
        if a.main != target.main { out.append("main \(a.main) != \(target.main)") }
        if a.mirror != target.mirror { out.append("mirror \(a.mirror) != \(target.mirror)") }
        return out
    }
}
