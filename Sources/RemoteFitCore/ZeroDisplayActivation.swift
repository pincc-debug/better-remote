import Foundation

/// How hard activation tries to bring up the virtual display. With zero online displays
/// (MacBook lid closed and the external monitor powered off, or a headless Mac whose only
/// screen went to sleep) WindowServer has no active framebuffer: CGVirtualDisplay creation
/// can fail transiently, the new display takes longer to come online, and its first mode
/// can arrive before the HiDPI mode is applied. None of that is a reason to give up: the
/// virtual display is exactly what restores a usable desktop for the remote session.
public struct ZeroDisplayActivation: Equatable, Sendable {
    public var createAttempts: Int
    public var createRetryDelay: TimeInterval
    public var readyPolls: Int
    public var readyPollInterval: TimeInterval
    /// Let commit/verification set the target mode instead of failing on the initial mode.
    public var acceptInitialModeMismatch: Bool
    /// Ask the power manager to wake the display pipeline before creating the display.
    public var wakeDisplays: Bool

    public static let standard = ZeroDisplayActivation(createAttempts: 1, createRetryDelay: 0, readyPolls: 20,
                                                       readyPollInterval: 0.15, acceptInitialModeMismatch: false,
                                                       wakeDisplays: false)
    public static let noDisplayOnline = ZeroDisplayActivation(createAttempts: 5, createRetryDelay: 0.5, readyPolls: 60,
                                                              readyPollInterval: 0.15, acceptInitialModeMismatch: true,
                                                              wakeDisplays: true)

    /// `live` is the snapshot taken right before creating the virtual display (after any
    /// leftover of ours was released).
    public static func policy(live: [DisplayState]) -> ZeroDisplayActivation {
        live.isEmpty ? .noDisplayOnline : .standard
    }
}
