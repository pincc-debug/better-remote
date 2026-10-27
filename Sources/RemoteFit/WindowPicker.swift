import AppKit
import RemoteFitCore

/// Select real windows with ordinary clicks. No overlay and no input interception.
@MainActor
final class WindowPicker {
    static let shared = WindowPicker()
    private let permissionCheck: () -> Bool
    init(permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) { self.permissionCheck = permissionCheck }
    private var session = WindowPickSession<Int>(needed: 1)
    private var timeout: Timer?
    private var onPlace: ((ScreenWindow, Int) -> Void)?
    private var onEnd: (() -> Void)?
    private var deadline: Timer?
    private var observers: [NSObjectProtocol] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressedWindow: ScreenWindow?
    private var receivedDown = false
    private var generation = 0
    private(set) var isActive = false

    @discardableResult
    func begin(_ arrangement: WindowArrangement, prepicked: ScreenWindow? = nil,
               place: @escaping (ScreenWindow, Int) -> Void, finished: @escaping () -> Void) -> Bool {
        end()
        guard permissionCheck(), arrangement.windowCount > (prepicked == nil ? 0 : 1) else { return false }
        session = WindowPickSession(needed: arrangement.windowCount, prepicked: prepicked.map { [$0.number] } ?? [])
        onPlace = place; onEnd = finished
        isActive = true
        let version = generation
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == version else { return }
                self.observe(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == version else { return }
                self.observe(event)
            }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else { end(); return false }
        restartTimeout()
        let cap = Timer(timeInterval: 60, target: self, selector: #selector(expired), userInfo: nil, repeats: false)
        RunLoop.main.add(cap, forMode: .common)
        deadline = cap
        let center = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.finish() } },
            ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.finish() } },
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.finish() } }
        ]
        OperationDiagnostics.write("window-pick-begin needed=\(arrangement.windowCount) prepicked=\(prepicked?.number ?? 0)")
        return true
    }

    func observe(_ event: NSEvent) {
        guard isActive else { return }
        if event.type == .leftMouseDown {
            restartTimeout()
            let point: CGPoint
            if let cg = event.cgEvent { point = cg.location }
            else {
                let mouse = NSEvent.mouseLocation
                point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
            }
            let excluded = Set(NSApp.windows.filter { !WindowControlPerformer.isRealWindow($0) }.map(\.windowNumber))
            if let window = NSApp.window(withWindowNumber: event.windowNumber), !WindowControlPerformer.isRealWindow(window) {
                pressedWindow = nil
            } else {
                pressedWindow = ScreenWindow.hit(point, in: WindowControlPerformer.screenWindows(), excluding: excluded)
            }
            receivedDown = true
            OperationDiagnostics.write("window-pick-down point=\(point) window=\(pressedWindow?.number ?? 0)")
        } else if event.type == .leftMouseUp, receivedDown {
            let hit = pressedWindow
            pressedWindow = nil; receivedDown = false
            let version = generation
            // Let the click finish in the real window before moving it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive, self.generation == version else { return }
                self.pick(hit)
            }
        }
    }

    private func pick(_ hit: ScreenWindow?) {
        let outcome = session.click(hit?.number)
        let slot = session.picked.count - 1
        OperationDiagnostics.write("window-pick-result window=\(hit?.number ?? 0) slot=\(slot) outcome=\(outcome)")
        if let hit, outcome != .finished { onPlace?(hit, slot) }
        if case .picked = outcome {} else { finish() }
    }

    private func finish() {
        guard isActive else { return }
        let done = onEnd
        end()
        if let done { DispatchQueue.main.async { done() } }
    }

    private func restartTimeout() {
        timeout?.invalidate()
        let timer = Timer(timeInterval: 15, target: self, selector: #selector(expired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        timeout = timer
    }
    @objc private func expired() { finish() }

    func end() {
        isActive = false
        generation += 1
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        pressedWindow = nil; receivedDown = false
        timeout?.invalidate(); timeout = nil
        deadline?.invalidate(); deadline = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        onPlace = nil; onEnd = nil
    }
}
