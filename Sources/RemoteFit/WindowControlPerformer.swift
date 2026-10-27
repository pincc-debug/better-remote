import AppKit
import ApplicationServices
import RemoteFitCore

/// Presses the frontmost window's own close / minimize / zoom controls through Accessibility.
@MainActor
enum WindowControlPerformer {
    /// Resolves toolbar exclusion in AppKit coordinates on the selected display.
    static var layoutArea: (NSScreen) -> CGRect = { $0.visibleFrame }
    static var prepareLayout: () async -> Void = {}
    private static let layoutController = WindowController()
    static var isAdjusting: Bool { layoutController.performing }

    private enum Target {
        case ax(WindowAXHandle), own(NSWindow)
    }

    // MARK: - Our own windows (Settings etc.)

    private static var lastOwnWindow: NSWindow?
    private static var tracking: NSObjectProtocol?
    /// Remembers our last real (non-panel) key window, since the toolbar never takes focus.
    static func startTracking() {
        guard tracking == nil else { return }
        tracking = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let window = NSApp.keyWindow, isRealWindow(window) { lastOwnWindow = window }
            }
        }
    }
    /// Toolbar, flyouts, notices and other helper panels are never targets; titled normal windows are.
    static func isRealWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled) && window.level == .normal
    }
    /// Our own window the controls should act on when Better Remote is frontmost.
    static func ownTarget() -> NSWindow? {
        [NSApp.keyWindow, NSApp.mainWindow, lastOwnWindow].compactMap { $0 }
            .first { isRealWindow($0) && $0.isVisible && !$0.isMiniaturized }
    }
    private static func ownWindows() -> [NSWindow] {
        NSApp.orderedWindows.filter { isRealWindow($0) && $0.isVisible && !$0.isMiniaturized }
    }
    private static func axFrame(of window: NSWindow) -> CGRect { WindowSnap.accessibilityRect(window.frame, primaryScreenHeight: primaryHeight) }
    private static func setOwnFrame(_ axRect: CGRect, of window: NSWindow) {
        window.setFrame(WindowSnap.accessibilityRect(axRect, primaryScreenHeight: primaryHeight), display: true, animate: false)
    }

    private static func performOwn(_ control: WindowControl, window: NSWindow) throws -> String? {
        switch control {
        case .close:
            guard window.styleMask.contains(.closable) else { throw FitError.message(control.unavailableMessage) }
            window.performClose(nil)
        case .minimize:
            guard window.styleMask.contains(.miniaturizable) else { throw FitError.message(control.unavailableMessage) }
            window.miniaturize(nil)
        case .fullScreen:
            if window.styleMask.contains(.resizable) {
                window.collectionBehavior.insert(.fullScreenPrimary)
                window.toggleFullScreen(nil)
            } else {
                throw FitError.message(control.unavailableMessage)
            }
        }
        return nil
    }

    /// Returns a short notice to show, if any.
    @discardableResult
    static func perform(_ control: WindowControl, pid: pid_t) async throws -> String? {
        if pid == getpid() {
            guard let window = ownTarget() else { throw FitError.message("没有可操作的窗口") }
            return try performOwn(control, window: window)
        }
        return try await WindowAXWorker.shared.perform(control, pid: pid)
    }

    // MARK: - Layouts (long-press on green)

    /// Moves the frontmost window to a layout on its own screen.
    static func snap(_ snap: WindowSnap, pid: pid_t) async throws {
        if pid == getpid() {
            guard let window = ownTarget() else { throw FitError.message("没有可操作的窗口") }
            try await snapOwn(snap, window: window)
            return
        }
        let (handle, current) = try await WindowAXWorker.shared.prepareSnap(pid: pid)
        try Task.checkCancellation()
        guard let area = visibleArea(for: current) else { throw FitError.message("当前窗口不能调整位置") }
        try await setFrame(snap.frame(current: current, in: area), handle: handle, pid: pid)
    }

    // MARK: - Toolbar 铺满 / 还原 toggle

    private static var fillToggle = FillToggle()

    /// Fills the frontmost window, or restores it (saved frame, else centered 2/3) when it is already filled.
    static func toggleFill(pid: pid_t) async throws {
        if pid == getpid() {
            guard let window = ownTarget() else { throw FitError.message("没有可操作的窗口") }
            if window.styleMask.contains(.fullScreen) { try await snapOwn(.fill, window: window); return }
            let current = axFrame(of: window)
            guard let area = visibleArea(for: current) else { throw FitError.message("当前窗口不能调整位置") }
            setOwnFrame(fillToggle.target(for: .init(pid: pid, window: window.windowNumber), current: current, area: area), of: window)
            return
        }
        let (handle, current) = try await WindowAXWorker.shared.prepareSnap(pid: pid)
        try Task.checkCancellation()
        guard let area = visibleArea(for: current) else { throw FitError.message("当前窗口不能调整位置") }
        let key = await frontScreenWindow(pid: pid).map { FillToggle.Key(pid: pid, window: $0.number) }
        try await setFrame(fillToggle.target(for: key, current: current, area: area), handle: handle, pid: pid)
    }

    /// Cheap periodic check: is the frontmost window filled? Also drops saved frames of closed
    /// windows and of windows the user resized away from filled.
    static func frontWindowIsFilled(pid: pid_t) async -> Bool {
        let visible = screenWindows().filter { $0.layer == 0 }
        let live = Set(visible.map { FillToggle.Key(pid: $0.pid, window: $0.number) })
        guard let front = await frontScreenWindow(pid: pid) else {
            fillToggle.observe(nil, frame: nil, area: nil, liveKeys: live); return false
        }
        return fillToggle.observe(.init(pid: pid, window: front.number), frame: front.bounds,
                                  area: visibleArea(for: front.bounds), liveKeys: live)
    }

    // MARK: - 远程时窗口自动铺满

    private static var autoFillTracker = AutoFillTracker()
    static func resetAutoFill() { autoFillTracker.reset() }

    /// Fills the app's front window with the same frame (and 还原 memory) as the toolbar's 铺满,
    /// when `AutoFillPolicy` allows it. Never touches our own windows; silent on any failure.
    static func autoFillFront(pid: pid_t) async {
        guard pid != getpid(), AXIsProcessTrusted() else { return }
        guard let (handle, probed) = await WindowAXWorker.shared.autoFillProbe(pid: pid), let frame = probed.frame else { return }
        let windows = screenWindows()
        autoFillTracker.retain(Set(windows.filter { $0.layer == 0 }.map { AutoFillTracker.Key(pid: $0.pid, window: $0.number) }))
        let distance = { (b: CGRect) in abs(frame.minX - b.minX) + abs(frame.minY - b.minY) + abs(frame.width - b.width) + abs(frame.height - b.height) }
        guard let match = windows.filter({ $0.pid == pid }).min(by: { distance($0.bounds) < distance($1.bounds) }),
              distance(match.bounds) < 40, let area = visibleArea(for: frame) else { return }
        var info = probed
        info.layer = match.layer
        let key = AutoFillTracker.Key(pid: pid, window: match.number)
        guard autoFillTracker.allows(key, frame: frame, area: area) else { return }
        let decision = AutoFillPolicy.decide(info, area: area)
        guard decision == .fill else {
            OperationDiagnostics.write("auto-fill skip pid=\(pid) reason=\(decision)")
            return
        }
        let target = fillToggle.target(for: FillToggle.Key(pid: pid, window: match.number), current: frame, area: area)
        do {
            try await setFrame(target, handle: handle, pid: pid)
            autoFillTracker.didFill(key)
            OperationDiagnostics.write("auto-fill pid=\(pid) window=\(match.number)")
        } catch {
            OperationDiagnostics.write("auto-fill failed pid=\(pid) error=\(error.localizedDescription)")
        }
    }

    // MARK: - 连接时的程序坞: follow the Dock

    /// Each screen's fill area (same as 铺满), in AX coordinates, keyed by display.
    static func layoutAreas() -> [CGDirectDisplayID: CGRect] {
        var areas: [CGDirectDisplayID: CGRect] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            areas[id] = WindowSnap.accessibilityRect(layoutArea(screen), primaryScreenHeight: primaryHeight)
        }
        return areas
    }

    /// Area pairs for the screens present both before and after.
    static func dockAreas(from old: [CGDirectDisplayID: CGRect]) -> [DockRefit.Area] {
        let new = layoutAreas()
        return old.compactMap { id, area in new[id].map { DockRefit.Area(old: area, new: $0) } }
    }

    /// Moves windows that were filling an old area to the new one (see `DockRefit`). Returns how many moved.
    static func refitFilledWindows(_ areas: [DockRefit.Area]) async -> Int {
        guard AXIsProcessTrusted() else { return 0 }
        let moves = DockRefit.plan(windows: screenWindows(), areas: areas, excludingPID: getpid())
        var moved = 0
        for move in moves {
            guard !Task.isCancelled, let handle = await WindowAXWorker.shared.resolve(move.window) else { continue }
            do {
                try await setFrame(move.target, handle: handle, pid: move.window.pid)
                moved += 1
            } catch {
                OperationDiagnostics.write("dock-refit failed pid=\(move.window.pid) error=\(error.localizedDescription)")
            }
        }
        if !moves.isEmpty { OperationDiagnostics.write("dock-refit moved=\(moved)/\(moves.count)") }
        return moved
    }

    static func snapOwn(_ snap: WindowSnap, window: NSWindow) async throws {
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            try await Task.sleep(for: .milliseconds(900))
        }
        let current = axFrame(of: window)
        guard let area = visibleArea(for: current) else { throw FitError.message("当前窗口不能调整位置") }
    setOwnFrame(snap.frame(current: current, in: area), of: window)
    }

    /// Windows currently on screen, front to back, in top-left coordinates.
    static func screenWindows() -> [ScreenWindow] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? Int, let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return ScreenWindow(number: number, pid: pid, bounds: bounds, layer: info[kCGWindowLayer as String] as? Int ?? 0)
        }
    }

    // MARK: - Picked layouts: each clicked window moves straight into its slot.

    private static var pickedCount = 0
    private static var pickedArea: CGRect?

    private static var pickedTask: Task<Void, Never>?
    private static var pickedErrors = 0
    private static var pickedLimited = 0
    private static var pickedGeneration = 0
    @discardableResult
    static func beginPicked() -> Int {
        pickedTask?.cancel()
        pickedGeneration += 1
        pickedCount = 0; pickedErrors = 0; pickedLimited = 0; pickedArea = nil
        return pickedGeneration
    }

    /// The frontmost app's target window as listed by the window server, for slot 1.
    static func frontScreenWindow(pid: pid_t) async -> ScreenWindow? {
        let windows = screenWindows().filter { $0.layer == 0 }
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let own = ownTarget() else { return nil }
            return windows.first { $0.number == own.windowNumber }
        }
        return await WindowAXWorker.shared.frontScreenWindow(pid: pid, windows: windows)
    }

    /// Moves one picked window into `slot` (0-based) right away.
    static func placePicked(_ arrangement: WindowArrangement, window item: ScreenWindow, slot: Int) {
        if pickedArea == nil { pickedArea = visibleArea(for: item.bounds) }
        guard let area = pickedArea else { return }
        let slots = arrangement.frames(available: arrangement.windowCount, in: area)
        guard slots.indices.contains(slot) else { return }
        let previous = pickedTask
        let generation = pickedGeneration
        pickedTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled, generation == pickedGeneration else { return }
            do {
                guard let target = await resolve(item) else { throw FitError.message("找不到所选窗口") }
                guard !Task.isCancelled, generation == pickedGeneration else { return }
                let result: WindowPlacementResult
                switch target {
                case .ax(let handle): result = try await setFrame(slots[slot], handle: handle, pid: item.pid, placementArea: area)
                case .own(let window): result = try placeOwn(slots[slot], window: window, in: area)
                }
                guard !Task.isCancelled, generation == pickedGeneration else { return }
                pickedCount += 1
                if result == .sizeLimited { pickedLimited += 1 }
                OperationDiagnostics.write("layout-placed pid=\(item.pid) slot=\(slot) result=\(result)")
            } catch {
                guard !Task.isCancelled, generation == pickedGeneration else { return }
                pickedErrors += 1
                OperationDiagnostics.write("layout-failed pid=\(item.pid) error=\(error.localizedDescription)")
            }
        }
    }

    /// Ends the session.
    static func endPicked(_ arrangement: WindowArrangement, generation expectedGeneration: Int? = nil) async -> String? {
        let generation = expectedGeneration ?? pickedGeneration
        guard generation == pickedGeneration else { return nil }
        await pickedTask?.value
        guard generation == pickedGeneration else { return nil }
        defer { pickedCount = 0; pickedErrors = 0; pickedLimited = 0; pickedArea = nil; pickedTask = nil }
        if pickedErrors > 0, pickedCount == 0 { return "未能排列窗口" }
        if pickedErrors > 0 { return "已排列 \(pickedCount) 个窗口，\(pickedErrors) 个未完成" }
        if pickedLimited > 0 { return "窗口尺寸受限" }
        return nil
    }

    private static func placeOwn(_ target: CGRect, window: NSWindow, in area: CGRect) throws -> WindowPlacementResult {
        setOwnFrame(target, of: window)
        let actual = axFrame(of: window)
        if WindowLayout.reached(actual, target: target, allowsSizeRounding: true) { return .placed }
        guard let constrained = WindowPlacement.constrainedFrame(actual, target: target, in: area) else {
            throw FitError.message("窗口未完成调整，请重试")
        }
        setOwnFrame(constrained, of: window)
        guard WindowLayout.reached(axFrame(of: window), target: constrained, allowsSizeRounding: true) else {
            throw FitError.message("窗口未完成调整，请重试")
        }
        return .sizeLimited
    }

    private static func resolve(_ item: ScreenWindow) async -> Target? {
        if item.pid == ProcessInfo.processInfo.processIdentifier {
            return NSApp.windows.first(where: { $0.windowNumber == item.number && isRealWindow($0) }).map(Target.own)
        }
        return await WindowAXWorker.shared.resolve(item).map(Target.ax)
    }

    /// AX coordinates are top-left based on the primary screen (the one holding the menu bar, origin 0,0).
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// Visible frame (no menu bar or Dock) of the screen holding the window, in AX coordinates.
    private static func visibleArea(for window: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        let full = screens.map { WindowSnap.accessibilityRect($0.frame, primaryScreenHeight: primaryHeight) }
        guard let index = WindowSnap.screenIndex(for: window, screens: full) else { return nil }
        let visible = layoutArea(screens[index])
        return WindowSnap.accessibilityRect(visible, primaryScreenHeight: primaryHeight)
    }

    @discardableResult
    private static func setFrame(_ target: CGRect, handle: WindowAXHandle, pid: pid_t,
                                 placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        await prepareLayout()
        try Task.checkCancellation()
        let result = try await layoutController.place(target, handle: handle, pid: pid, placementArea: placementArea)
        OperationDiagnostics.write("window-frame target=\(NSStringFromRect(target))")
        return result
    }

}
