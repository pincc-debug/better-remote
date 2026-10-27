import Foundation

// Adapted from UU LightSlide (https://github.com/Dameon020/uu-lightslide).
// Copyright (c) 2026 Rixin Zhao and contributors. MIT; see THIRD_PARTY_NOTICES.md.

public enum UUScrollScaling {
    public static let defaultPercent = 100
    public static func clampedPercent(_ value: Int) -> Int { min(100, max(1, value)) }

    /// Match actual UU app components, not a process name or arbitrary path substring.
    public static func isUUExecutable(_ path: String) -> Bool {
        guard let range = path.range(of: "/UURemote.app/Contents/") else { return false }
        return ["MacOS/UURemote", "MacOS/UURemoteService", "MacOS/UURemoteDaemon",
                "Helpers/UURemoteServer",
                "XPCServices/UURemoteHelper.xpc/Contents/MacOS/UURemoteHelper"]
            .contains(String(path[range.upperBound...]))
    }
}

/// Preserve subpixel movement at low speed, but never carry it into another gesture or target.
public struct UUScrollAccumulator: Sendable {
    private var remainderX = 0.0, remainderY = 0.0
    private var lastX = 0.0, lastY = 0.0
    private var lastTime = -Double.infinity
    private var lastContext = ""
    public init() {}
    public mutating func reset() { self = Self() }

    public mutating func scale(x: Double, y: Double, percent: Int, time: TimeInterval,
                               context: String) -> (x: Int32, y: Int32) {
        if context != lastContext || time - lastTime > 0.35 || time < lastTime {
            remainderX = 0; remainderY = 0; lastX = 0; lastY = 0
        }
        if x * lastX < 0 { remainderX = 0 }
        if y * lastY < 0 { remainderY = 0 }
        let fraction = Double(UUScrollScaling.clampedPercent(percent)) / 100
        remainderX += (x.isFinite ? x : 0) * fraction
        remainderY += (y.isFinite ? y : 0) * fraction
        let quantize = { (v: Double) in Int32(max(Double(Int32.min), min(Double(Int32.max), v.rounded(.towardZero)))) }
        let ix = quantize(remainderX), iy = quantize(remainderY)
        remainderX -= Double(ix); remainderY -= Double(iy)
        if x != 0 { lastX = x }; if y != 0 { lastY = y }
        lastTime = time; lastContext = context
        return (ix, iy)
    }
}
