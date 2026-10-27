import Foundation

/// Decides whether the current displays can be the base of a new session.
/// Anything that is not a Better Remote virtual display (real monitors, HDMI dummies, and
/// system/remote-tool virtual screens on a headless Mac) is a base display: it gets mirrored
/// during the session and restored exactly afterwards. Only a leftover display of ours, or a
/// mirror pointing outside the set, blocks activation.
public enum ActivationBase {
    public static let ownVendor: UInt32 = 0x5246
    public enum Verdict: Equatable { case ok, ownLeftover([UInt32]), brokenMirror([UInt32]) }

    public static func isOwn(hardwareKey: String) -> Bool { hardwareKey.hasPrefix("\(ownVendor):") }

    public static func verdict(_ states: [DisplayState]) -> Verdict {
        let own = states.filter { isOwn(hardwareKey: $0.hardwareKey) }.map(\.id)
        if !own.isEmpty { return .ownLeftover(own) }
        let byID = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let broken = states.filter { s in s.mirror != 0 && (byID[s.mirror].map { $0.mirror != 0 } ?? true) }.map(\.id)
        return broken.isEmpty ? .ok : .brokenMirror(broken)
    }
}
