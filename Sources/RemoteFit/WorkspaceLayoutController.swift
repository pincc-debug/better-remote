import AppKit
import ApplicationServices
import RemoteFitCore

/// While expanded, move only actual overlaps after window/app changes or drag release.
/// No unconditional focused-window fill or mouse-event interception.
@MainActor
final class WorkspaceLayoutController {
    struct Region: Equatable {
        let area: CGRect
        let screen: CGRect
        let toolbar: CGRect
        let side: ToolbarSide
    }
    var region: () -> Region? = { nil }
    /// Windows the user just laid out (窗口 layouts) stay put even when they overlap the toolbar.
    var isExempt: (ApplicationWindowCatalog.Window) -> Bool = { _ in false }
    private let visibleWindows: () async -> [ApplicationWindowCatalog.Window]
    private let canAdjust: () -> Bool
    private let userInteracting: () -> Bool
    private let foregroundPID: () -> pid_t?
    private let move: (ApplicationWindowCatalog.Window, Region) async -> Void
    private let fill: (ApplicationWindowCatalog.Window, Region) async -> Void
    private var task: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var timer: Timer?
    private var enabled = false
    private var generation = 0
    private var lastWindows: [ApplicationWindowCatalog.Window]?
    private var lastRegion: Region?
    private var lastForeground: pid_t?

    convenience init(windows: WindowController) {
        self.init(visibleWindows: { await ApplicationWindowCatalog.shared.snapshot() },
                  canAdjust: { AXIsProcessTrusted() && !windows.performing && !WindowControlPerformer.isAdjusting },
                  userInteracting: { NSEvent.pressedMouseButtons != 0 },
                  fill: { candidate, region in
            await windows.fillCollapsedToolbar(candidate, toolbar: region.toolbar, screen: region.screen, side: region.side)
        }, move: { candidate, region in
            await windows.moveAsideFromToolbar(candidate, toolbar: region.toolbar, screen: region.screen, side: region.side)
        })
    }

    init(visibleWindows: @escaping () async -> [ApplicationWindowCatalog.Window],
         canAdjust: @escaping () -> Bool, userInteracting: @escaping () -> Bool,
         foregroundPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         fill: @escaping (ApplicationWindowCatalog.Window, Region) async -> Void = { _, _ in },
         move: @escaping (ApplicationWindowCatalog.Window, Region) async -> Void) {
        self.visibleWindows = visibleWindows
        self.canAdjust = canAdjust
        self.userInteracting = userInteracting
        self.foregroundPID = foregroundPID
        self.move = move
        self.fill = fill
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        cancel()
        guard value else { return }
        enabled = true
        // First tick follows the expansion animation. Later ticks observe changes,
        // including apps that do not deliver AX window-moved notifications.
        schedule(WorkspaceCheckSchedule.active)
        let center = NSWorkspace.shared.notificationCenter
        appObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applicationChanged() }
            }
        }
    }

    private var appObservers: [NSObjectProtocol] = []
    private var schedule = WorkspaceCheckSchedule()
    private var interval: TimeInterval = 0

    private func schedule(_ next: TimeInterval) {
        guard enabled, next != interval || timer == nil else { return }
        interval = next
        timer?.invalidate()
        let timer = Timer(timeInterval: next, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = next * 0.12
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Launching/activating apps are busy with WindowServer; give them a moment before checking.
    private func applicationChanged() {
        guard enabled else { return }
        schedule.pause(now: ProcessInfo.processInfo.systemUptime)
        schedule(schedule.interval)
    }

    private func tick() {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if schedule.isPaused(now: now) { return }
        defer { schedule(schedule.interval) }
        if userInteracting() {
            schedule.changed()
            cancelPending()
            lastWindows = nil
            return
        }
        guard task == nil, canAdjust(), let captured = region() else { return }
        let version = generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == version { task = nil; schedule(schedule.interval) } }
            let windows = await visibleWindows()
            guard !Task.isCancelled, enabled, generation == version, region() == captured,
                  canAdjust(), !userInteracting() else { return }
            let snapshot = windows.sorted { $0.id < $1.id }
            let front = foregroundPID()
            guard snapshot != lastWindows || captured != lastRegion || front != lastForeground else {
                schedule.unchanged(); return
            }
            schedule.changed()
            lastWindows = snapshot; lastRegion = captured; lastForeground = front
            for candidate in windows {
                guard !Task.isCancelled, enabled, generation == version, region() == captured,
                      canAdjust(), !userInteracting() else { return }
                guard !isExempt(candidate), WindowLayout.avoidingToolbar(candidate.frame,
                    toolbar: captured.toolbar, screen: captured.screen, side: captured.side) != nil else { continue }
                await move(candidate, captured)
            }
        }
    }

    private func cancelPending() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func cancel() {
        enabled = false
        timer?.invalidate()
        timer = nil
        interval = 0
        schedule = WorkspaceCheckSchedule()
        appObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers = []
        cancelPending()
        collapseTask?.cancel()
        collapseTask = nil
        lastWindows = nil
    }

    func releaseToolbar() {
        let pending = task
        let captured = region()
        cancel()
        guard let captured else { return }
        let version = generation
        collapseTask = Task { @MainActor [weak self] in
            await pending?.value
            guard let self else { return }
            defer { if generation == version { collapseTask = nil } }
            guard !Task.isCancelled, !enabled, generation == version else { return }
            let candidates = await visibleWindows().filter {
                WindowLayout.fillingCollapsedToolbar($0.frame, toolbar: captured.toolbar,
                    screen: captured.screen, side: captured.side) != nil
            }
            for candidate in candidates {
                guard !Task.isCancelled, !enabled, generation == version,
                      canAdjust(), !userInteracting() else { return }
                await fill(candidate, captured)
            }
        }
    }

    func suspendCurrentAdjustment() async {
        let pending = task
        let pendingFill = collapseTask
        cancelPending()
        collapseTask?.cancel()
        collapseTask = nil
        lastWindows = nil
        await pending?.value
        await pendingFill?.value
    }
}
