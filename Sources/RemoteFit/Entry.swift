import AppKit
import Foundation
import NativeDisplay
import RemoteFitCore

@main
struct Entry {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--check-todesk-accessibility" {
            UUSilentAccessibilityCheck.run(bundleID: "com.youqu.todesk.mac")
            UUSilentAccessibilityCheck.run(bundleID: "com.youqu.todesk.mac.tdsvc")
            return
        }
        if args.first == "--check-uu-window-cycle" {
            Task { @MainActor in
                let result = await UUWindowIdentification.identify()
                let output: [String: Any] = ["status": result.status, "minimized": result.minimized.map { $0 as Any } ?? NSNull(),
                    "device": result.device?.name ?? "", "id": result.device?.id ?? ""]
                if let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                }
                exit(0)
            }
            dispatchMain()
        }
        if args.first == "--check-uu-accessibility" {
            UUSilentAccessibilityCheck.run()
            return
        }
        if args.first == "--check-input-relay" {
            _ = NSApplication.shared
            Task { @MainActor in
                let relay = ShortcutEventRelay()
                relay.prepare()
                guard relay.isPrepared, let marker = CGEvent(source: nil) else {
                    print("input-relay: unavailable")
                    exit(1)
                }
                relay.post([marker])
                relay.finishWhenIdle()
                await relay.waitUntilDelivered()
                for _ in 0..<100 where relay.isPrepared { try? await Task.sleep(for: .milliseconds(10)) }
                print(relay.isPrepared ? "input-relay: cleanup failed" : "input-relay: delivery and cleanup OK")
                exit(relay.isPrepared ? 1 : 0)
            }
            NSApplication.shared.run()
            return
        }
        if args.first == "--remote-status" {
            Task {
                let snapshot = await RemoteSessionProbe().sample()
                let result: [String: Any] = [
                    "active": RemoteSoftware.allCases.filter { snapshot.active.contains($0) }.map(\.rawValue),
                    "unknown": RemoteSoftware.allCases.filter { snapshot.unknown.contains($0) }.map(\.rawValue)
                ]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                }
                exit(0)
            }
            dispatchMain()
        }
        if args.first == "--worker" { exit(DisplayWorker.execute(Array(args.dropFirst()))) }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/RemoteFit")
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        if args.first == "--check" {
            do {
                guard RFVirtualDisplay.isAvailable() else { throw FitError.message("当前系统不支持虚拟屏幕") }
                let devices = try DisplayWorker.snapshot()
                print("Native virtual display API: OK; displays: \(devices.count)")
                exit(0)
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }
        if args.first == "--restore" {
            Task { @MainActor in
                do {
                    let lock = try InstanceLock(root: root)
                    let engine = DisplayEngine(root: root, executable: executable)
                    try await engine.restore()
                    withExtendedLifetime(lock) {}
                    print("PASS: physical display restoration and full-height mode")
                    exit(0)
                } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if args.first == "--smoke" {
            Task { @MainActor in
              do {
                let lock = try InstanceLock(root: root)
                let preset = args.count > 1 ? ScreenPreset(rawValue: args[1]) ?? .phone : .phone
                let size = args.count > 2 ? DisplaySize(rawValue: args[2]) ?? .standard : .standard
                let engine = DisplayEngine(root: root, executable: executable)
                if args.contains("--capture-replacement") {
                    try await engine.smokeCaptureReplacement()
                } else if args.contains("--adjustments") {
                    try await engine.smokeAdjustments()
                } else if args.contains("--manual") {
                    try await engine.smokeManual()
                } else {
                    try await engine.smoke(dimensions: preset.dimensions(size), injectFailure: args.contains("--inject-failure"))
                }
                withExtendedLifetime(lock) {}
                let scenario = args.contains("--capture-replacement") ? "direct display handoff, fresh capture identities and retained-source rollback" :
                    (args.contains("--adjustments") ? "direct display handoff, fresh capture identities and retained-source rollback" :
                    (args.contains("--manual") ? "standalone 1366×768" : preset.dimensions(size).label))
                print("PASS: \(scenario), HiDPI, mirror source, restore")
                exit(0)
              } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let controller = AppController(root: root, executable: executable)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
