import Foundation
import IOKit.pwr_mgt
import NativeDisplay
import RemoteFitCore

struct EngineStatus: Sendable, Equatable {
    var title: String
    var detail: String? = nil
    var active: Bool = false
    var applied: Dimensions? = nil
}

actor DisplayEngine {
    let root: URL
    let executable: String
    var virtualDisplay: RFVirtualDisplay?
    var applied: Dimensions? { didSet { if applied == nil { appliedMode = nil } } }
    private var appliedMode: DisplayMode?
    var recovered = false
    var pendingRestore = false
    var shuttingDown = false
    private var lastDisplaySerial: UInt32 = 1
    let encoder = JSONEncoder()
    var sessionURL: URL { root.appendingPathComponent("session.json") }
    var stableURL: URL { root.appendingPathComponent("stable-layouts.json") }
    lazy var stableModes: StableModes = (try? JSONDecoder().decode(StableModes.self, from: Data(contentsOf: stableURL))) ?? StableModes()
    var stableBaseline: [DisplayState]?
    var stableWindowStart: Double = 0
    /// Uptime when our last activation/restore (including re-checks) finished.
    var lastDisplayWork: Double = 0
    private var idleForStable: Bool { !hasSession() && virtualDisplay == nil && applied == nil && !shuttingDown }
    /// A display change happened (or launch): remember the state at the start of the settle window.
    func noteRemoteActivity() { lastDisplayWork = ProcessInfo.processInfo.systemUptime; stableBaseline = nil }
    func beginStableWindow() {
        stableWindowStart = ProcessInfo.processInfo.systemUptime
        stableBaseline = idleForStable ? (try? snapshot()) : nil
    }
    /// End of a quiet settle window: record modes that did not change during it.
    func finishStableWindow() {
        defer { stableBaseline = nil }
        guard let baseline = stableBaseline, idleForStable, stableWindowStart > lastDisplayWork,
              baseline.allSatisfy(\.physical), let live = try? snapshot(), live.allSatisfy(\.physical),
              stableWindowStart > lastDisplayWork else { return }
        if stableModes.record(baseline: baseline, live: live) {
            log("stable_layout", Self.layout(live))
            try? encoder.encode(stableModes).write(to: stableURL, options: .atomic)
        }
    }
    init(root: URL, executable: String) {
        self.root = root; self.executable = executable
    }
    func log(_ event: String, _ detail: String = "") {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("RemoteFit.log")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("RemoteFit.previous.log"))
            try? FileManager.default.moveItem(at: url, to: root.appendingPathComponent("RemoteFit.previous.log"))
        }
        if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(ISO8601DateFormatter().string(from: Date())) \(event) \(detail)\n".utf8))
    }
    func snapshot() throws -> [DisplayState] {
        let args = ["--worker", "snapshot"]
        return try JSONDecoder().decode([DisplayState].self, from: ProcessRunner.run(executable, args, timeout: 12))
    }
    func commit(_ targets: [DisplayState]) throws {
        let data = try ProcessRunner.run(executable, ["--worker", "commit"], input: encoder.encode(CommitRequest(targets: targets)), timeout: 12)
        if let result = try? JSONDecoder().decode([String: Int].self, from: data), let changed = result["changedDisplays"] {
            log("display_commit", "targets=\(targets.count) changed=\(changed)")
        }
    }
    func save(_ states: [DisplayState]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(states).write(to: sessionURL, options: .atomic)
    }
    func hasSession() -> Bool { FileManager.default.fileExists(atPath: sessionURL.path) }
    private func restorationTargets(_ targets: [DisplayState]) throws -> [DisplayState] {
        let data = try ProcessRunner.run(executable, ["--worker", "normalize-restore"],
                                         input: encoder.encode(CommitRequest(targets: targets)), timeout: 12)
        let normalized = try JSONDecoder().decode([DisplayState].self, from: data)
        for target in normalized {
            if let original = targets.first(where: { $0.id == target.id }), !original.mode.matches(target.mode) {
                log("full_height_restore", "id=\(target.id) \(original.mode.width)×\(original.mode.height) -> \(target.mode.width)×\(target.mode.height) refresh=\(target.mode.refresh)")
            }
        }
        return normalized
    }

    private func restoreFullHeightIfNeeded() throws {
        let live = try snapshot()
        guard live.allSatisfy({ $0.physical && $0.mirror == 0 }) else { return }
        let targets = try restorationTargets(live)
        let changed = targets.filter { target in live.first(where: { $0.id == target.id })?.mode.matches(target.mode) == false }
            .map { target in var target = target; target.skipOrigin = true; return target }
        guard !changed.isEmpty else { return }
        try commit(changed)
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.2)
            let after = try snapshot()
            for target in targets {
                guard let actual = after.first(where: { $0.id == target.id }), actual.mode.matches(target.mode),
                      actual.x == target.x, actual.y == target.y, actual.main == target.main, actual.mirror == target.mirror else {
                    throw FitError.message("屏幕完整高度还原未通过校验")
                }
            }
        }
    }
    private func createDisplay(_ dimensions: Dimensions, policy: ZeroDisplayActivation = .standard) throws -> RFVirtualDisplay {
        guard RFVirtualDisplay.isAvailable() else { throw FitError.message("当前系统不支持虚拟屏幕。") }
        for attempt in 1...max(1, policy.createAttempts) {
            var serial: UInt32
            repeat { serial = UInt32.random(in: 2...UInt32.max) } while serial == lastDisplaySerial
            lastDisplaySerial = serial
            if let display = RFVirtualDisplay(width: UInt32(dimensions.width), height: UInt32(dimensions.height), serialNumber: serial),
               display.displayID != 0 {
                if attempt > 1 { log("display_create_recovered", "attempt=\(attempt)") }
                return display
            }
            log("display_create_retry", "attempt=\(attempt)/\(policy.createAttempts)")
            if attempt < policy.createAttempts {
                if policy.wakeDisplays { wakeDisplays() }
                Thread.sleep(forTimeInterval: policy.createRetryDelay)
            }
        }
        throw FitError.message("无法创建虚拟屏幕。")
    }
    /// With zero online displays the display pipeline may be powered down; declaring user
    /// activity wakes it (same effect as a key press) so CGVirtualDisplay can come online.
    private func wakeDisplays() {
        var id: IOPMAssertionID = 0
        if IOPMAssertionDeclareUserActivity("Better Remote virtual display" as CFString, kIOPMUserActiveLocal, &id) == kIOReturnSuccess {
            IOPMAssertionRelease(id)
        }
    }
    private func readySource(id: UInt32, dimensions: Dimensions, policy: ZeroDisplayActivation = .standard) throws -> ReadyVirtualDisplay {
        var lastProbe: VirtualDisplayProbe?
        var loggedModes: Data?
        do {
            let ready = try VirtualDisplayReadiness.wait(dimensions: dimensions, policy: policy, sample: {
                let data = try ProcessRunner.run(executable, ["--worker", "probe-virtual", String(id)], timeout: 12)
                let probe = try JSONDecoder().decode(VirtualDisplayProbe.self, from: data)
                lastProbe = probe
                let modes = try encoder.encode(probe.modes)
                if modes != loggedModes {
                    loggedModes = modes
                    log("display_mode_probe", "id=\(id) target=\(dimensions.label) actual=\(Self.layout(probe.source.map { [$0] } ?? [])) modes=\(String(decoding: modes, as: UTF8.self))")
                }
                return probe
            }, pause: { Thread.sleep(forTimeInterval: $0) })
            let density = ready.mode.pixelWidth == dimensions.width * 2 ? "hidpi" : "standard"
            log("display_mode_selected", "id=\(id) density=\(density) mode=\(String(decoding: try encoder.encode(ready.mode), as: UTF8.self))")
            log("display_created", "id=\(id) uuid=\(ready.source.uuid ?? "nil") target=\(dimensions.label)")
            return ready
        } catch {
            log("display_mode_unavailable", "id=\(id) target=\(dimensions.label) online=\(lastProbe?.source != nil) reason=\(error.localizedDescription)")
            throw error
        }
    }

    private func verifyTransition(_ targets: [DisplayState], sourceID: UInt32, disappearingID: UInt32? = nil) throws {
        let expectedIDs = Set(targets.map(\.id))
        var consecutiveMatches = 0
        for attempt in 0..<10 {
            let live = HeadlessPlaceholder.ignoringPlaceholders(try snapshot())
            let liveIDs = Set(live.map(\.id))
            guard liveIDs == expectedIDs || disappearingID.map({ liveIDs == expectedIDs.union([$0]) }) == true else {
                throw FitError.message("适配期间显示器硬件拓扑发生变化，操作已中止。")
            }
            if DisplayTransition.matches(live, targets: targets, sourceID: sourceID) {
                consecutiveMatches += 1
                if consecutiveMatches >= 2 {
                    log("display_mode_verified", "source=\(sourceID) actual=\(Self.layout(live))")
                    return
                }
            } else {
                consecutiveMatches = 0
                if attempt == 3 || attempt == 7 {
                    // Re-apply the source mode and any independent physical display macOS re-defaulted.
                    let drifted = targets.filter { target in
                        guard target.id == sourceID || (target.physical && target.mirror == 0),
                              let actual = live.first(where: { $0.id == target.id }) else { return false }
                        return !actual.mode.matches(target.mode)
                    }
                    if !drifted.isEmpty {
                        log("mode_reapply", "attempt=\(attempt) ids=\(drifted.map(\.id))")
                        try commit(drifted.map { var t = $0; t.skipOrigin = true; return t })
                    }
                }
            }
            if attempt < 9 { Thread.sleep(forTimeInterval: 0.2) }
        }
        log("verification_failed", String(decoding: try encoder.encode(snapshot()), as: UTF8.self))
        throw FitError.message("分辨率切换后未能通过状态校验")
    }
    func activate(_ dimensions: Dimensions, injectFailure: Bool = false, recoveryData: Data? = nil,
                  injectFailureAfterSwitch: Bool = false) throws {
        guard CustomPreset.isSupported(dimensions) else { throw FitError.message("分辨率超出支持范围。") }
        if virtualDisplay != nil, applied != nil, hasSession() {
            try replaceDisplay(dimensions, injectFailure: injectFailure, injectFailureAfterSwitch: injectFailureAfterSwitch)
            return
        }
        var recoveryData = recoveryData
        if hasSession() {
            if try !restore(), virtualDisplay != nil, applied != nil {
                try replaceDisplay(dimensions, injectFailure: injectFailure, injectFailureAfterSwitch: injectFailureAfterSwitch)
                return
            }
            // Restore deferred with no live virtual display: keep the original snapshot.
            if hasSession(), recoveryData == nil { recoveryData = try Data(contentsOf: sessionURL) }
        }
        // An empty list is a headless Mac (no physical display online); that is supported.
        var live = try snapshot()
        if case .ownLeftover = ActivationBase.verdict(live) {
            // Our own display is never a conflict: it outlived its session state (headless deferred
            // restore, monitor powered off) or is still being torn down. Release it and wait it out.
            log("own_virtual_leftover", "held=\(virtualDisplay?.displayID ?? 0) \(Self.layout(live))")
            virtualDisplay = nil; applied = nil
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.2)
                live = try snapshot()
                if case .ownLeftover = ActivationBase.verdict(live) { continue }
                break
            }
        }
        // A mode switched by the remote tool at connect time must not become the restore point.
        let (saved, fixed) = stableModes.corrected(live)
        if !fixed.isEmpty { log("snapshot_layout_corrected", "live=\(Self.layout(live)) using=\(Self.layout(saved))") }
        let verdict = ActivationBase.verdict(saved)
        guard verdict == .ok else {
            log("display_conflict", "verdict=\(verdict) displays=\(Self.layout(saved)) keys=\(saved.map { "\($0.id):\($0.hardwareKey):\($0.uuid ?? "-")" }.joined(separator: " "))")
            throw FitError.message("检测到系统当前正在使用其他虚拟屏幕或屏幕镜像。请先关闭冲突的显示设置，再应用分辨率。")
        }
        if saved.contains(where: { $0.mirror != 0 }) { log("base_mirror_set", Self.layout(saved)) }
        if let recoveryData { try recoveryData.write(to: sessionURL, options: .atomic) }
        else { try save(saved) }
        let start = ProcessInfo.processInfo.systemUptime
        let policy = ZeroDisplayActivation.policy(live: live)
        if policy.wakeDisplays {
            // MacBook lid closed with the external monitor powered off, or a headless Mac asleep.
            log("no_display_online", "creating virtual display without a base display")
            wakeDisplays()
        }
        do {
            virtualDisplay = try createDisplay(dimensions, policy: policy)
            guard let sourceID = virtualDisplay?.displayID else { throw FitError.message("无法创建虚拟屏幕。") }
            let ready = try readySource(id: sourceID, dimensions: dimensions, policy: policy)
            let mirrorable = HeadlessPlaceholder.mirrorable(saved)
            if mirrorable.count != saved.count {
                log("headless_placeholder_skipped", "ids=\(saved.filter(HeadlessPlaceholder.isPlaceholder).map(\.id))")
            }
            let targets = try DisplayTransition.targets(source: ready.source, dimensions: dimensions, physical: mirrorable, selectedMode: ready.mode)
            if injectFailure { throw FitError.message("测试：模拟屏幕切换失败") }
            try commit(targets)
            try verifyTransition(targets, sourceID: sourceID)
            applied = dimensions
            appliedMode = ready.mode
            lastDisplayWork = ProcessInfo.processInfo.systemUptime
            log("activated", "\(dimensions.label) seconds=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - start))")
        } catch {
            log("activation_failed", error.localizedDescription)
            // The half-made display is never kept, even when restoration is deferred.
            virtualDisplay = nil; applied = nil
            do { try restore() } catch { throw FitError.message("适配未能完成，且桌面还原异常：\(error.localizedDescription)") }
            throw error
        }
    }
    private func replaceDisplay(_ dimensions: Dimensions, injectFailure: Bool, injectFailureAfterSwitch: Bool) throws {
        guard let previous = applied, let previousID = virtualDisplay?.displayID else { throw FitError.message("尚未应用分辨率") }
        let recoveryData = try Data(contentsOf: sessionURL)
        let before = HeadlessPlaceholder.ignoringPlaceholders(try snapshot())
        guard let oldSource = before.first(where: { $0.id == previousID }), oldSource.main,
              before.filter({ $0.id != previousID }).allSatisfy({ $0.physical && ($0.mirror == previousID || $0.mirror == 0) }),
              before.contains(where: { $0.mirror == previousID }) || !before.contains(where: \.physical) else {
            throw FitError.message("显示器布局已变化，请先还原屏幕")
        }
        let physical = before.filter(\.physical)
        log("display_replacement_start", "\(previous.label) -> \(dimensions.label)")
        var candidate: RFVirtualDisplay?
        var candidateTarget: DisplayState?
        var attemptedSwitch = false
        var retiredOld = false
        do {
            // Keep the current desktop until the new capture identity is ready.
            candidate = try createDisplay(dimensions)
            guard let candidateID = candidate?.displayID else { throw FitError.message("无法创建虚拟屏幕。") }
            let ready = try readySource(id: candidateID, dimensions: dimensions)
            let targets = try DisplayTransition.targets(source: ready.source, dimensions: dimensions, physical: physical, retiring: oldSource, selectedMode: ready.mode)
            candidateTarget = targets.first(where: { $0.id == candidateID })
            if injectFailure { throw FitError.message("测试：模拟屏幕切换失败") }
            attemptedSwitch = true
            try commit(targets)
            try verifyTransition(targets, sourceID: candidateID)
            if injectFailureAfterSwitch { throw FitError.message("测试：模拟屏幕交接后失败") }
            // Physical mirrors already use the new source; retire the old one last.
            virtualDisplay = candidate
            candidate = nil
            retiredOld = true
            try verifyTransition(targets.filter { $0.id != previousID }, sourceID: candidateID, disappearingID: previousID)
            applied = dimensions
            appliedMode = ready.mode
            log("display_handoff", "old=\(previousID) new=\(candidateID) physical_restore=false")
            log("display_replacement_complete", dimensions.label)
        } catch {
            let failure = error
            log("display_replacement_failed", failure.localizedDescription)
            var recoveredInPlace = false
            if !retiredOld {
                do {
                    if attemptedSwitch, let candidateTarget {
                        let rollback = try DisplayTransition.targets(source: oldSource, dimensions: previous, physical: physical, retiring: candidateTarget, selectedMode: oldSource.mode)
                        try commit(rollback)
                        try verifyTransition(rollback, sourceID: previousID)
                    }
                    let disappearingID = candidate?.displayID
                    candidate = nil
                    let rollback = try DisplayTransition.targets(source: oldSource, dimensions: previous, physical: physical, selectedMode: oldSource.mode)
                    try verifyTransition(rollback, sourceID: previousID, disappearingID: disappearingID)
                    applied = previous
                    appliedMode = oldSource.mode
                    recoveredInPlace = true
                    log("display_replacement_rolled_back", "\(previous.label) source_retained=true")
                } catch { log("display_handoff_recovery_failed", error.localizedDescription) }
            }
            if recoveredInPlace { throw failure }
            candidate = nil
            do {
                try restore()
                try activate(previous, recoveryData: recoveryData)
                log("display_replacement_rolled_back", "\(previous.label) source_retained=false")
            } catch {
                log("display_replacement_rollback_failed", error.localizedDescription)
                throw FitError.message("切换及恢复上次规格失败：\(error.localizedDescription)")
            }
            throw failure
        }
    }
    /// Returns false when restoration is deferred because no physical display is online:
    /// the virtual display stays (a Mac with zero displays breaks remote access) and the
    /// snapshot is kept until a monitor comes back.
    @discardableResult
    func restore() throws -> Bool {
        guard hasSession() else {
            // No restore point means nothing may keep our display alive.
            if virtualDisplay != nil { log("own_virtual_released", "no_session"); virtualDisplay = nil }
            applied = nil; pendingRestore = false; try restoreFullHeightIfNeeded(); return true
        }
        let saved = try JSONDecoder().decode([DisplayState].self, from: Data(contentsOf: sessionURL))
        if try headless(saved: saved) {
            pendingRestore = true
            log("restore_deferred", "no_physical_display virtual_kept=\(virtualDisplay != nil)")
            return false
        }
        let start = ProcessInfo.processInfo.systemUptime
        var last: Error = FitError.message("桌面还原未能完成。")
        for attempt in 1...3 {
            do {
                virtualDisplay = nil
                applied = nil
                Thread.sleep(forTimeInterval: 0.2)
                var live = try snapshot()
                // Migrate recovery snapshots from earlier versions using hardware identity.
                let savedKeys = Set(saved.map(\.hardwareKey))
                for i in live.indices where savedKeys.contains(live[i].hardwareKey) { live[i].physical = true }
                var targets: [DisplayState]
                switch try RestorePlan.outcome(saved: saved, live: live) {
                case .restore(let planned): targets = try restorationTargets(planned)
                case .release: targets = []; log("restore_release", "original_displays_absent")
                case .deferred: throw FitError.message("显示器已断开，稍后自动还原。")
                }
                if !targets.isEmpty { try commit(targets) }
                Thread.sleep(forTimeInterval: 0.2)
                let after = try snapshot()
                let mismatched = targets.compactMap { target -> String? in
                    let diff = StableModes.mismatches(target: target, actual: after.first(where: { $0.id == target.id }))
                    return diff.isEmpty ? nil : "id=\(target.id) " + diff.joined(separator: "; ")
                }
                if !mismatched.isEmpty {
                    log("restore_mismatch", mismatched.joined(separator: " | "))
                    // macOS may normalise an origin we asked for; modes, main and mirroring are what matter.
                    let onlyOrigin = targets.allSatisfy { target in
                        StableModes.mismatches(target: target, actual: after.first(where: { $0.id == target.id })).allSatisfy { $0.hasPrefix("origin") }
                    }
                    if !(onlyOrigin && attempt == 3) {
                        throw FitError.message("桌面还原校验未通过。已保存恢复快照，请重新尝试还原或检查显示器连接。")
                    }
                    log("restore_origin_normalized", "accepted macOS placement")
                    // Re-checks keep macOS's placement instead of fighting it.
                    for i in targets.indices { if let a = after.first(where: { $0.id == targets[i].id }) { targets[i].x = a.x; targets[i].y = a.y } }
                }
                let restoredIDs = Set(targets.map(\.id))
                guard after.filter({ !restoredIDs.contains($0.id) }).allSatisfy(\.physical) else {
                    throw FitError.message("仍有虚拟屏幕未断开，请关闭其他显示工具后重试。")
                }
                log("restore_layout", "saved=\(Self.layout(saved)) after=\(Self.layout(after))")
                try? FileManager.default.removeItem(at: root.appendingPathComponent("session.last.json"))
                try? FileManager.default.copyItem(at: sessionURL, to: root.appendingPathComponent("session.last.json"))
                try FileManager.default.removeItem(at: sessionURL)
                applied = nil
                pendingRestore = false
                reassertRestoredModes(targets)
                lastDisplayWork = ProcessInfo.processInfo.systemUptime
                log("restored", "seconds=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime-start))")
                return true
            } catch { last = error; log("restore_retry", "\(attempt) \(error.localizedDescription)"); Thread.sleep(forTimeInterval: 0.2) }
        }
        // Never let an unreachable snapshot block every later activation: if only physical,
        // unmirrored displays remain (nothing of ours is left), retire the snapshot.
        if let live = try? snapshot(), !live.isEmpty, live.allSatisfy({ $0.physical && $0.mirror == 0 }) {
            let failed = root.appendingPathComponent("session.failed.json")
            try? FileManager.default.removeItem(at: failed)
            try? FileManager.default.moveItem(at: sessionURL, to: failed)
            applied = nil; pendingRestore = false
            lastDisplayWork = ProcessInfo.processInfo.systemUptime
            log("restore_abandoned", "live=\(Self.layout(live)) reason=\(last.localizedDescription)")
            return true
        }
        throw last
    }
    /// macOS can switch an external monitor to its default (HiDPI) mode shortly after the
    /// virtual display goes away, after our first verification already passed. Re-check at
    /// ~1s and ~3s and put the saved mode back if it drifted.
    private func reassertRestoredModes(_ targets: [DisplayState]) {
        let modeTargets = targets
        guard !modeTargets.isEmpty else { return }
        for delay in [1.0, 2.0] {
            Thread.sleep(forTimeInterval: delay)
            guard let live = try? snapshot() else { continue }
            let drifted = RestoreDrift.drifted(targets: modeTargets, live: live)
            guard !drifted.isEmpty else { continue }
            for d in drifted {
                let now = live.first { $0.id == d.id }?.mode
                log("restore_mode_reasserted", "id=\(d.id) live=\(now.map { "\($0.pixelWidth)x\($0.pixelHeight)/\($0.width)x\($0.height)" } ?? "?") target=\(d.mode.pixelWidth)x\(d.mode.pixelHeight)/\(d.mode.width)x\(d.mode.height)")
            }
            do { try commit(drifted.count == 1 ? drifted : modeTargets) }
            catch { log("restore_mode_reassert_failed", error.localizedDescription) }
        }
    }
    static func layout(_ states: [DisplayState]) -> String {
        states.map { "\($0.id)\($0.main ? "*" : ""):\($0.mode.pixelWidth)x\($0.mode.pixelHeight)/\($0.mode.width)x\($0.mode.height)@\($0.x),\($0.y)m\($0.mirror)" }.joined(separator: " ")
    }
    private func headless(saved: [DisplayState]) throws -> Bool {
        var live = try snapshot()
        let savedKeys = Set(saved.map(\.hardwareKey))
        for i in live.indices where savedKeys.contains(live[i].hardwareKey) { live[i].physical = true }
        return try RestorePlan.outcome(saved: saved, live: live) == .deferred
    }
    /// Called when displays change: finishes a deferred restore once a monitor is back.
    func resumePendingRestore() -> Bool {
        guard pendingRestore, !shuttingDown, hasSession() else { return false }
        do { return try restore() } catch { log("restore_resume_failed", error.localizedDescription); return false }
    }
    func isRestorePending() -> Bool { pendingRestore }
    func report(_ title: String, detail: String? = nil) -> EngineStatus {
        .init(title: title, detail: detail, active: applied != nil, applied: applied)
    }
    func initialize() -> EngineStatus {
        do {
            if !recovered {
                if hasSession() { _ = try restore() }
                recovered = true
            }
            guard RFVirtualDisplay.isAvailable() else { throw FitError.message("当前系统不支持虚拟屏幕。") }
            return report(applied.map { "已应用 · \($0.label)" } ?? "就绪")
        } catch {
            return report(hasSession() ? "待还原屏幕" : "检测未通过", detail: error.localizedDescription)
        }
    }
    func apply(_ dimensions: Dimensions) -> EngineStatus {
        guard !shuttingDown else { return report("正在还原…") }
        let ready = initialize()
        guard ready.detail == nil else { return ready }
        do {
            if applied != dimensions { try activate(dimensions) }
            let standard = appliedMode.map { $0.pixelWidth == $0.width } ?? false
            return report("已应用 · \(dimensions.label)" + (standard ? " · 标准清晰度" : ""))
        } catch {
            log("error", error.localizedDescription)
            return report(applied != nil ? "切换未完成" : (hasSession() ? "待还原屏幕" : "应用未完成"), detail: error.localizedDescription)
        }
    }
    func shutdown() throws { shuttingDown = true; do { _ = try restore() } catch { shuttingDown = false; throw error } }
    func smokeManual() throws {
        var preferences = Preferences()
        let custom = CustomPreset(name: "Native smoke", width: 1366, height: 768)
        preferences.customPresets = [custom]; preferences.selectedCustomID = custom.id
        do {
            let applied = apply(preferences.dimensions)
            guard applied.applied == preferences.dimensions else { throw FitError.message(applied.detail ?? "手动应用失败") }
            Thread.sleep(forTimeInterval: 2.5)
            let held = initialize()
            guard held.applied == preferences.dimensions else { throw FitError.message("本地分辨率未保持") }
            try restore()
        } catch { try restore(); throw error }
    }
    func smokeAdjustments() throws { try smokeCaptureReplacement() }
    func smokeCaptureReplacement() throws {
        do {
            var identities = Set<String>()
            var recovery: Data?
            let dimensions = [Dimensions(1252, 1156), Dimensions(630, 1400), Dimensions(1024, 768), Dimensions(1400, 630)]
            for size in dimensions {
                let result = apply(size)
                guard result.detail == nil, result.applied == size,
                      let source = try snapshot().first(where: { !$0.physical && $0.main }),
                      let uuid = source.uuid, identities.insert(uuid).inserted else {
                    throw FitError.message(result.detail ?? "采集屏幕身份未更新")
                }
                let saved = try Data(contentsOf: sessionURL)
                if let recovery {
                    guard saved == recovery else { throw FitError.message("更换采集屏幕改变了恢复记录") }
                } else { recovery = saved }
                let repeated = apply(size)
                guard repeated.detail == nil,
                      try snapshot().first(where: { !$0.physical && $0.main })?.uuid == uuid else {
                    throw FitError.message("重复选择同一规格不应更换屏幕")
                }
            }
            let invalid = apply(.init(4000, 900))
            guard invalid.detail != nil, invalid.applied == dimensions.last,
                  try Data(contentsOf: sessionURL) == recovery else {
                throw FitError.message("无效规格改变了当前屏幕")
            }
            let retainedUUID = try snapshot().first(where: { !$0.physical && $0.main })?.uuid
            for afterSwitch in [false, true] {
                var failed = false
                do { try activate(.init(1280, 800), injectFailure: !afterSwitch, injectFailureAfterSwitch: afterSwitch) }
                catch { failed = true }
                guard failed, applied == dimensions.last,
                      let source = try snapshot().first(where: { !$0.physical && $0.main }),
                      source.mode.width == 1400, source.mode.height == 630,
                      source.uuid == retainedUUID,
                      try Data(contentsOf: sessionURL) == recovery else {
                    throw FitError.message("采集屏幕交接失败后未保留上次屏幕")
                }
            }
            try restore()
        } catch { try restore(); throw error }
    }
    func smoke(dimensions: Dimensions, injectFailure: Bool) throws {
        do { try activate(dimensions, injectFailure: injectFailure); try restore() }
        catch { try restore(); throw error }
    }
}
