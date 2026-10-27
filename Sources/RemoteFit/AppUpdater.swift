import AppKit
import Sparkle

/// 自动更新：包装标准更新控制器，只在正式打包的应用里启动。
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController?

    /// 只有打包好的 .app（Info.plist 带有更新源）才启动，测试和命令行运行时不启动。
    var isAvailable: Bool { controller != nil }

    func start() {
        guard controller == nil,
              Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        // 自动检查是固定行为：每 3 小时一次，忽略任何旧的本地设置。
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.updateCheckInterval = 10800
        controller.updater.automaticallyDownloadsUpdates = false
    }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
