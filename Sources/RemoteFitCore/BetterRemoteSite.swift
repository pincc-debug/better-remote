import Foundation

/// Official Better Remote site URLs. Keep one origin so help/API never diverge.
public enum BetterRemoteSite {
    public static let origin = URL(string: "https://betterremote.pincc.dev")!
    public static let help = origin.appending(path: "help")
    public static let diagnosticLogs = origin.appending(path: "api/diagnostic-logs")
    public static let rewardQR = origin.appending(path: "qr/reward.png")
}
