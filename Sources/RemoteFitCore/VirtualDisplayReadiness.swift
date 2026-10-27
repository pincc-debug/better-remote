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
    /// Standard density is eligible only at the deadline, from the final live sample.
    public static func wait(dimensions: Dimensions, policy: ZeroDisplayActivation,
                            sample: () throws -> VirtualDisplayProbe, pause: (TimeInterval) -> Void) throws -> ReadyVirtualDisplay {
        let polls = max(1, policy.readyPolls)
        for attempt in 0..<polls {
            let probe = try sample()
            if let source = probe.source, !source.physical, source.mirror == 0 {
                if let mode = select(probe.modes, dimensions: dimensions, scale: 2) {
                    return .init(source: source, mode: mode)
                }
                if attempt == polls - 1 {
                    if let mode = select(probe.modes, dimensions: dimensions, scale: 1) {
                        return .init(source: source, mode: mode)
                    }
                    throw FitError.message("系统未提供 \(dimensions.label) 显示模式。")
                }
            }
            if attempt < polls - 1 { pause(policy.readyPollInterval) }
        }
        throw FitError.message("虚拟屏幕未就绪。")
    }
}
