import AppKit
import NativeDisplay

/// Events wake the detector. A slow safety check covers lost notifications and
/// clients whose session helper starts after their power assertion is created.
@MainActor
final class RemoteSessionMonitor {
    private let notifications = RFAssertionNotifications()
    private var fallback: Timer?
    private var confirmation: Timer?
    private var pending: Task<Void, Never>?
    private var observation: NSKeyValueObservation?
    private var wake: NSObjectProtocol?
    private var sample: (@MainActor () async -> TimeInterval?)?
    private var generation = 0
    private var lastSample = -Double.infinity
    private var dirty = false

    func start(sample: @escaping @MainActor () async -> TimeInterval?) {
        stop()
        self.sample = sample
        let available = notifications.start { [weak self] in
            MainActor.assumeIsolated { self?.request() }
        }
        let timer = Timer(timeInterval: available ? 30 : 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.request() }
        }
        timer.tolerance = available ? 3 : 1
        fallback = timer
        RunLoop.main.add(timer, forMode: .common)
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let relevant = { (apps: [NSRunningApplication]) in
                Set(apps.filter { app in
                    let path = app.bundleURL?.path ?? ""
                    return path.contains("/ToDesk") || path.contains("/UURemote") || path.contains("/AnyDesk") || path.contains("/RustDesk.app")
                }.map(\.processIdentifier))
            }
            guard relevant(change.oldValue ?? []) != relevant(change.newValue ?? []) else { return }
            Task { @MainActor [weak self] in self?.request() }
        }
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.request() }
        }
        request()
    }

    func stop() {
        generation += 1
        notifications.stop()
        fallback?.invalidate(); fallback = nil
        confirmation?.invalidate(); confirmation = nil
        pending?.cancel(); pending = nil
        observation = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        wake = nil
        sample = nil
        dirty = false
        lastSample = -Double.infinity
    }

    private func request() {
        guard sample != nil else { return }
        guard pending == nil else { dirty = true; return }
        let version = generation
        let delay = max(0, lastSample + 1 - ProcessInfo.processInfo.systemUptime)
        pending = Task { [weak self] in
            do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } }
            catch { return }
            guard let self, version == generation, let sample else { return }
            lastSample = ProcessInfo.processInfo.systemUptime
            let next = await sample()
            guard !Task.isCancelled, version == generation else { return }
            pending = nil
            confirmation?.invalidate(); confirmation = nil
            if let next {
                let timer = Timer(timeInterval: max(0.05, next), repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.request() }
                }
                confirmation = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            if dirty { dirty = false; request() }
        }
    }
}
