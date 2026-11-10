import Foundation

public struct VirtualDisplayProbe: Codable, Sendable {
    public var source: DisplayState?
    public var modes: [DisplayMode]
    public init(source: DisplayState?, modes: [DisplayMode]) {
        self.source = source; self.modes = modes
    }
}

public struct ReadyVirtualDisplay: Sendable {
    public var source: DisplayState
    public var mode: DisplayMode
}

public enum VirtualDisplayReadiness {
    public static func isCompatible(_ mode: DisplayMode, dimensions: Dimensions, scale: Int) -> Bool {
        mode.width == dimensions.width && mode.height == dimensions.height &&
            mode.pixelWidth == dimensions.width * scale && mode.pixelHeight == dimensions.height * scale &&
            abs(mode.refresh - 60) < 1
    }

    /// Only exact desktop sizes are eligible. Never substitute a nearby size or stretch it.
    public static func select(_ modes: [DisplayMode], dimensions: Dimensions, scale: Int) -> DisplayMode? {
        modes.filter { isCompatible($0, dimensions: dimensions, scale: scale) }
            .min { abs($0.refresh - 60) < abs($1.refresh - 60) }
    }

    /// Wait for advertised HiDPI modes, not for macOS to select one automatically.
    /// Standard density is eligible only at the deadline. A single empty sample after a
    /// usable one is treated as flicker (the display was online); two empty samples at
    /// the end are a display that went away, and its earlier modes are not reused.
    public static func wait(dimensions: Dimensions, policy: ZeroDisplayActivation,
                            sample: () throws -> VirtualDisplayProbe, pause: (TimeInterval) -> Void) throws -> ReadyVirtualDisplay {
        let polls = max(1, policy.readyPolls)
        var previous: VirtualDisplayProbe?
        for attempt in 0..<polls {
            let probe = try sample()
            let prior = previous
            previous = probe
            if let ready = hidpi(probe, dimensions: dimensions) { return ready }
            if attempt == polls - 1 {
                let candidates = usable(probe) != nil ? [probe] : [probe, prior].compactMap { $0 }
                for candidate in candidates {
                    if let ready = hidpi(candidate, dimensions: dimensions) { return ready }
                    if usable(candidate) != nil {
                        if let mode = select(candidate.modes, dimensions: dimensions, scale: 1), let source = usable(candidate) {
                            return .init(source: source, mode: mode)
                        }
                        throw FitError.message("系统未提供 \(dimensions.label) 显示模式。")
                    }
                }
            } else {
                pause(policy.readyPollInterval)
            }
        }
        throw FitError.message("虚拟屏幕未就绪。")
    }

    private static func usable(_ probe: VirtualDisplayProbe?) -> DisplayState? {
        guard let source = probe?.source, !source.physical, source.mirror == 0 else { return nil }
        return source
    }

    private static func hidpi(_ probe: VirtualDisplayProbe, dimensions: Dimensions) -> ReadyVirtualDisplay? {
        guard let source = usable(probe), let mode = select(probe.modes, dimensions: dimensions, scale: 2) else { return nil }
        return .init(source: source, mode: mode)
    }
}
