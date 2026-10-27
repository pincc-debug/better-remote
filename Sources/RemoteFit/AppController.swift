import ServiceManagement
import AppKit
import SwiftUI
import Foundation
import RemoteFitCore
import Darwin
import ApplicationServices

final class InstanceLock {
    private let descriptor: Int32
    init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        descriptor = Darwin.open(root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw FitError.message("无法创建应用运行锁。") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw FitError.message("Better Remote 已在运行中，请在顶部菜单栏查看对应图标。")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let root: URL
    let engine: DisplayEngine
    private var instanceLock: InstanceLock?
    private var item: NSStatusItem?
    private var preferences = Preferences()
    private var adjustment = ResolutionAdjustment(Preferences().dimensions)
    private var status = EngineStatus(title: "正在检测运行环境…")
    private var terminating = false
    private var applying = false
    private var copySaved = false
    private var applyGeneration = 0
    private var terminationSignals: [DispatchSourceSignal] = []
    private let panelModel = ControlPanelModel()
    private var settingsWindow: NSWindow?
    private var settingsDragScroll: WindowDragScroll?
    private let floatingSwitcher = FloatingSwitcher()
    private let touchScroll = UUTouchScroll()
    private var touchScrollRetry: Timer?
    private let nativeScroll = UUNativeScroll()
    private var nativeScrollTimer: Timer?
    private let windowController = WindowController()
    private let notice = TransientNotice()
    private lazy var workspaceLayout = WorkspaceLayoutController(windows: windowController)
    private var windowActionTask: Task<Void, Never>?
    private var windowActionGeneration = 0
    private var arrangementTask: Task<Void, Never>?
    private var resolutionWindow: NSWindow?
    /// Measured content height of the 分辨率 panel; the panel shrinks to it.
    private var resolutionContentHeight: CGFloat?
    private let appLauncher: AppLauncher
    private let remoteProbe = RemoteSessionProbe()
    private let remoteMonitor = RemoteSessionMonitor()
    private var remoteStability = RemoteSessionStability()
    private var deviceCollection = RemoteDeviceCollection()
    private var remoteDeviceID: String?
    private var lastMatchedDeviceID: String?
    private var connectionDockPolicy = ConnectionDockPolicy()
    private var connectionToolbarPolicy = ConnectionToolbarPolicy()
    /// 连接时的程序坞: the user's own autohide value while we owe it back (persisted for crash recovery).
    private var dockSession = ConnectionDockSession(originalAutohide: DockAutohideBridge.persistedOriginal)
    private var connectionDockTask: Task<Void, Never>?
    private var connectionDockSyncAgain = false
    private var dockPermissionNoticeShown = false
    /// 远程连接时显示 / 未连接时显示: which setting applies now (disconnects wait 5 s).
    private var toolbarPresence = ToolbarPresence()
    private var toolbarPresenceTimer: Timer?
    private let autoFill = AutoFillController()
    private var automaticPolicy = AutomaticResolutionPolicy()
    private struct AutomaticRestorePoint {
        let preset: ScreenPreset
        let size: DisplaySize
        let selectedCustomID: String?
        let adjustment: ResolutionAdjustment
    }
    private var automaticRestorePoint: AutomaticRestorePoint?


    init(root: URL, executable: String) {
        self.root = root; engine = DisplayEngine(root: root, executable: executable)
        appLauncher = AppLauncher(root: root)
        super.init()
        if let data = try? Data(contentsOf: root.appendingPathComponent("preferences.json")),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = saved }
        adjustment = preferences.resolutionAdjustment
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { instanceLock = try InstanceLock(root: root) }
        catch { NSApplication.shared.terminate(nil); return }
        AppUpdater.shared.start()
        NSApplication.shared.setActivationPolicy(.accessory)
        scheduleStableModeRecord()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumePendingRestoreIfPossible(); self?.scheduleStableModeRecord() }
        }
        // Resolution changed while 设置 is open (e.g. to a phone-portrait mode): keep it on screen.
        // The visible frame can settle a moment later, so fit again shortly after.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fitSettingsWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.fitSettingsWindow() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.fitSettingsWindow() }
            }
        }
        applyTheme()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item?.button?.image = Self.statusImage(active: false)
        item?.button?.toolTip = "Better Remote"
        workspaceLayout.region = { [weak self] in
            guard let self, !applying, !terminating, floatingSwitcher.isExpanded,
                  let screen = floatingSwitcher.actionScreen else { return nil }
            let visible = WindowController.accessibilityFrame(screen)
            let toolbar = floatingSwitcher.reservedToolbarFrame
            let appKitArea = DesktopToolbarLayout.workspace(avoiding: toolbar, in: screen.visibleFrame, side: preferences.toolbarSide)
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let area = CGRect(x: appKitArea.minX, y: top - appKitArea.maxY, width: appKitArea.width, height: appKitArea.height)
            let axToolbar = CGRect(x: toolbar.minX, y: top - toolbar.maxY, width: toolbar.width, height: toolbar.height)
            return WorkspaceLayoutController.Region(area: area, screen: visible, toolbar: axToolbar, side: preferences.toolbarSide)
        }
        WindowControlPerformer.prepareLayout = { [weak self] in await self?.workspaceLayout.suspendCurrentAdjustment() }
        WindowControlPerformer.layoutArea = { [weak self] screen in
            guard let self, floatingSwitcher.actionScreen == screen else { return screen.visibleFrame }
            return DesktopToolbarLayout.workspace(presence: floatingSwitcher.presence, toolbar: floatingSwitcher.toolbarFrame,
                                                  in: screen.visibleFrame, side: preferences.toolbarSide)
        }
        autoFill.perform = { pid in await WindowControlPerformer.autoFillFront(pid: pid) }
        autoFill.canFill = { [weak self] in self.map { !$0.applying && !$0.terminating && $0.connectionDockTask == nil } ?? false }
        // touchScroll.isOwnWindow defaults to a thread-safe WindowServer hit test (runs on the tap thread).
        startTouchScroll()
        configurePanel()
        startNativeScroll()
        floatingSwitcher.configure(preferences: preferences)
        applyToolbarSetting()
        // SIGTERM follows the same restore-before-exit path as the menu item.
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume(); terminationSignals.append(source)
        }
        checkEnvironment()
        automaticPolicy.setEnabled(preferences.autoResolutionEnabled)
        automaticPolicy.restoreOnDisconnect = preferences.autoRestoreOnDisconnect
        connectionDockPolicy.setEnabled(preferences.connectionDockMode != .keep)
        startRemoteMonitor()
        // A previous run quit or crashed while it had changed the Dock: give the user's setting back.
        if dockSession.owesRestore { syncConnectionDock() }
        // Manual launch: bring Settings to front. Login-item launch stays quiet
        // (menu bar + toolbar only) unless Accessibility is missing.
        if !Self.launchedAsLoginItem || !AXIsProcessTrusted() {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }
    private static var launchedAsLoginItem: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem { return true }
        // SMAppService login items are started by launchd without that flag; treat a launch
        // shortly after boot while registered as a login launch.
        return SMAppService.mainApp.status == .enabled && ProcessInfo.processInfo.systemUptime < 300
    }
    private func checkEnvironment() {
        guard !applying, !terminating else { return }
        applying = true; renderMenu()
        Task {
            let result = await engine.initialize()
            guard !terminating else { return }
            status = result; applying = false; renderMenu(); runAutomaticResolutionIfNeeded()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if instanceLock == nil { return .terminateNow }
        if terminating { return .terminateLater }
        terminating = true
        connectionDockTask?.cancel(); connectionDockTask = nil
        applyGeneration += 1
        automaticPolicy.manualOverride()
        automaticRestorePoint = nil
        notice.dismiss()
        touchScrollRetry?.invalidate(); touchScrollRetry = nil
        touchScroll.stop()
        nativeScrollTimer?.invalidate(); nativeScrollTimer = nil
        nativeScroll.stop()
        remoteMonitor.stop()
        workspaceLayout.cancel()
        windowActionTask?.cancel()
        arrangementTask?.cancel()
        WindowPicker.shared.end()
        toolbarPresenceTimer?.invalidate(); toolbarPresenceTimer = nil
        autoFill.setEnabled(false)
        floatingSwitcher.setEnabled(false)
        status = .init(title: "正在还原屏幕…"); renderMenu()
        // AppKit can wait in a nested run loop inside terminate(). A main-queue Task
        // cannot start there, so run restoration off that queue and reply via CFRunLoop.
        Task.detached { [engine, owner = self] in
            // Give back the user's Dock setting (queued after any in-flight Dock write).
            let dockResult = DockAutohideBridge.shared.restorePersistedNow()
            await engine.log("connection_dock_quit", dockResult)
            let failure: String?
            do { try await engine.shutdown(); failure = nil }
            catch { failure = error.localizedDescription }
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { owner.finishTermination(failure: failure) }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        return .terminateLater
    }
    private func finishTermination(failure: String?) {
        guard let failure else {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
            return
        }
        terminating = false
        applying = false
        dockSession = ConnectionDockSession(originalAutohide: DockAutohideBridge.persistedOriginal)
        applyToolbarSetting()
        status = .init(title: "桌面还原未完成", detail: failure)
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
        startRemoteMonitor()
        startNativeScroll()
        renderMenu()
    }
    private func save() {
        do { try JSONEncoder().encode(preferences).write(to: root.appendingPathComponent("preferences.json"), options: .atomic) }
        catch { status = .init(title: "设置保存失败", detail: error.localizedDescription) }
        renderMenu()
    }
    private func applyTheme() {
        switch preferences.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    /// The status menu is text only. AppKit attaches SF Symbols to some items on its own
    /// (e.g. a gear for an `openSettings` action), so ask it not to display any item image.
    static func hideMenuItemImages(in menu: NSMenu) {
        guard #available(macOS 27.0, *) else { return }
        for item in menu.items where !item.isSeparatorItem {
            item.preferredImageVisibility = .hidden
            if let submenu = item.submenu { hideMenuItemImages(in: submenu) }
        }
    }
    private func configurePanel() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let floatingItem = NSMenuItem(title: "显示工具条", action: #selector(toggleFloating), keyEquivalent: "")
        floatingItem.target = self; floatingItem.tag = 1; menu.addItem(floatingItem)
        let restoreItem = NSMenuItem(title: "还原本机分辨率", action: #selector(recover), keyEquivalent: "")
        restoreItem.target = self; restoreItem.tag = 2; menu.addItem(restoreItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self; menu.addItem(settingsItem)
        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self; menu.addItem(updateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Better Remote", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self; menu.addItem(quitItem)
        Self.hideMenuItemImages(in: menu)
        menu.delegate = self
        item?.menu = menu
        appLauncher.onAction = { [weak self] action in
            if action == .resolution { self?.showResolution() }
            else { self?.showSettings() }
        }
        appLauncher.onHide = { [weak self] in self?.floatingSwitcher.setActivePanel(nil) }
        appLauncher.onShow = { [weak self] in self?.floatingSwitcher.setActivePanel(.runningApplications) }
        floatingSwitcher.onDismissPanels = { [weak self] in self?.dismissToolPanels() }
        floatingSwitcher.onWillCollapse = { [weak self] in self?.workspaceLayout.releaseToolbar() }
        floatingSwitcher.onExpansionChanged = { [weak self] in
            guard let self else { return }
            renderMenu()
        }
        floatingSwitcher.companionFrame = { [weak self] in
            guard let self else { return nil }
            if appLauncher.isVisible { return appLauncher.visibleFrame }
            return resolutionWindow?.isVisible == true ? resolutionWindow?.frame : nil
        }
        floatingSwitcher.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .resolution: showResolution()
            case .runningApplications: showApplications()
            case .restoreDisplay: recover()
            case .settings: showSettings()
            case .maximizeWindow, .centerWindow:
                performWindowAction(action)
            case .fillWindow:
                performFillToggle()
            case .minimizeWindow:
                performWindowControl(.minimize)
            case .showDesktop:
                performShowDesktop()

            }
        }
        floatingSwitcher.onWindowControl = { [weak self] control in self?.performWindowControl(control) }
        floatingSwitcher.onWindowSnap = { [weak self] snap in self?.performWindowSnap(snap) }
        floatingSwitcher.fillTargetPID = { [weak self] in self?.windowControlTargetPID() }
        floatingSwitcher.onArrange = { [weak self] in self?.performArrange($0) }
        WindowControlPerformer.startTracking()
        installWindowDebugHook()
        // Cap every AX call app-wide so an unresponsive target app can never stall the main thread for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        panelModel.onSaveApplicationShortcuts = { [weak self] groups, enabled in
            guard let self else { return false }
            var next = preferences
            next.applicationShortcuts = groups
            next.applicationShortcutsEnabled = enabled
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                panelModel.preferences = next
                floatingSwitcher.configure(preferences: next)
                renderMenu()
                return true
            } catch {
                OperationDiagnostics.write("application-shortcut-save write-failed error=\(error.localizedDescription)")
                status = .init(title: "保存失败", detail: error.localizedDescription)
                renderMenu()
                return false
            }
        }
        panelModel.onSaveShortcut = { [weak self] shortcut in
            guard let self, shortcut.isValid else { return false }
            var next = preferences
            if let index = next.namedShortcuts.firstIndex(where: { $0.id == shortcut.id }) { next.namedShortcuts[index] = shortcut }
            else {
                next.operationOrder = next.orderedOperations.map(\.id)
                next.namedShortcuts.append(shortcut)
                next.operationOrder.append(ConfiguredOperation.shortcutID(shortcut.id))
            }
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                floatingSwitcher.configure(preferences: preferences)
            } catch { status.title = "保存失败"; status.detail = error.localizedDescription; renderMenu(); return false }
            renderMenu()
            return true
        }
        panelModel.onDeleteShortcut = { [weak self] id in
            guard let self else { return false }
            var next = preferences
            next.namedShortcuts.removeAll { $0.id == id }
            next.operationOrder.removeAll { $0 == ConfiguredOperation.shortcutID(id) }
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                floatingSwitcher.configure(preferences: preferences)
                renderMenu()
                return true
            } catch {
                status = .init(title: "删除失败", detail: error.localizedDescription)
                renderMenu()
                return false
            }
        }
        panelModel.onShortcutToggle = { [weak self] id, enabled in
            guard let self, let index = preferences.namedShortcuts.firstIndex(where: { $0.id == id }) else { return }
            preferences.namedShortcuts[index].enabled = enabled
            save()
            floatingSwitcher.configure(preferences: preferences)
        }
        panelModel.onFloatingActionIcon = { [weak self] action, icon in
            guard let self else { return false }
            var next = preferences
            next.floatingActionIcons[action.rawValue] = icon.rawValue
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                floatingSwitcher.configure(preferences: next)
                renderMenu()
                return true
            } catch {
                status = .init(title: "保存失败", detail: error.localizedDescription)
                renderMenu()
                return false
            }
        }
        panelModel.onFloatingActionToggle = { [weak self] action, enabled in
            guard let self else { return }
            if enabled {
                if !preferences.floatingActions.contains(action) { preferences.floatingActions.append(action) }
            } else {
                preferences.floatingActions.removeAll { $0 == action }
            }
            save()
            floatingSwitcher.configure(preferences: preferences)
        }
        panelModel.onMoveOperations = { [weak self] offsets, destination in
            guard let self else { return }
            var next = preferences
            next.moveOperations(from: offsets, to: destination)
            guard next.operationOrder != preferences.operationOrder else { return }
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                floatingSwitcher.configure(preferences: preferences)
            } catch {
                status = .init(title: "排序保存失败", detail: error.localizedDescription)
            }
            renderMenu()
        }
        panelModel.onToolbarSide = { [weak self] side in
            guard let self else { return }
            dismissToolPanels()
            preferences.toolbarSide = side
            floatingSwitcher.configure(preferences: preferences)
            save()
        }
        panelModel.onTheme = { [weak self] theme in
            guard let self, theme != preferences.theme else { return }
            var next = preferences
            next.theme = theme
            do {
                try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
                preferences = next
                applyTheme()
            } catch {
                status = .init(title: "主题保存失败", detail: error.localizedDescription)
            }
            renderMenu()
        }
        // Menu bar 显示工具条: a manual, temporary override; the next connect / disconnect applies the settings again.
        panelModel.onFloatingToggle = { [weak self] enabled in
            guard let self, !terminating else { return }
            if enabled { floatingSwitcher.showExpanded() } else { floatingSwitcher.setEnabled(false) }
            renderMenu()
        }
        panelModel.onToolbarWhenConnectedToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.toolbarWhenConnected = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onToolbarWhenDisconnectedToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.toolbarWhenDisconnected = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onAutoFillWindowsToggle = { [weak self] enabled in
            guard let self else { return }
            if enabled, !AXIsProcessTrusted() { ShortcutPermissions.shared.prepare { [weak self] in self?.renderMenu() } }
            var next = preferences
            next.autoFillWindowsOnRemote = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onAutoResolutionToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.setAutomaticResolutionEnabled(enabled)
            saveAutomaticPreferences(next)
        }
        panelModel.onAutoResolutionPreset = { [weak self] id in
            guard let self else { return }
            var next = preferences
            next.autoResolutionPresetID = next.customPresets.contains(where: { $0.id == id }) ? id : nil
            saveAutomaticPreferences(next)
        }
        panelModel.onDefaultResolutionToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.defaultResolutionEnabled = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onDeviceResolutionToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.deviceResolutionEnabled = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onDeleteRemoteDevice = { [weak self] id in
            guard let self else { return }
            var next = preferences
            deviceCollection.remove(id, from: &next)
            saveAutomaticPreferences(next)
        }
        panelModel.onDeviceResolutionPreset = { [weak self] deviceID, presetID in
            guard let self, let index = preferences.remoteDevices.firstIndex(where: { $0.id == deviceID }) else { return }
            var next = preferences
            next.remoteDevices[index].presetID = next.customPresets.contains(where: { $0.id == presetID }) ? presetID : nil
            saveAutomaticPreferences(next)
        }
        panelModel.onAutoRestoreToggle = { [weak self] enabled in
            guard let self else { return }
            var next = preferences
            next.autoRestoreOnDisconnect = enabled
            saveAutomaticPreferences(next)
        }
        panelModel.onUUTouchScrollToggle = { [weak self] enabled in
            guard let self else { return }
            let wasMonitoring = preferences.needsRemoteConnectionMonitoring
            preferences.uuTouchScrollEnabled = enabled
            save()
            if wasMonitoring != preferences.needsRemoteConnectionMonitoring { startRemoteMonitor() }
            if enabled, !AXIsProcessTrusted() { ShortcutPermissions.shared.prepare { [weak self] in self?.startTouchScroll() } }
            startTouchScroll()
        }
        panelModel.onUUScrollSpeedPercent = { [weak self] value in
            guard let self else { return }
            let percent = UUScrollScaling.clampedPercent(value)
            guard percent != preferences.uuScrollSpeedPercent else { return }
            preferences.uuScrollSpeedPercent = percent
            nativeScroll.setPercent(percent)
            save()
            startNativeScroll()
            if percent < 100, !AXIsProcessTrusted() {
                ShortcutPermissions.shared.prepare { [weak self] in self?.refreshNativeScroll() }
            }
        }
        panelModel.onWindowControlsToggle = { [weak self] enabled in
            guard let self else { return }
            preferences.showWindowControls = enabled
            save()
            panelModel.preferences = preferences
            floatingSwitcher.configure(preferences: preferences)
        }
        panelModel.onConnectionDockMode = { [weak self] mode in
            guard let self, mode != preferences.connectionDockMode else { return }
            var next = preferences
            next.connectionDockMode = mode
            saveAutomaticPreferences(next)
        }
        panelModel.onScale = { [weak self] percent in
            guard let self, !applying, !terminating,
                  let next = adjustment.settingScale(percent) else { return }
            guard next != adjustment else { dismissToolPanels(); return }
            adjustment = next; copySaved = false
            if let id = preferences.selectedCustomID,
               let index = preferences.customPresets.firstIndex(where: { $0.id == id }),
               let preset = preferences.customPresets[index].settingScale(percent) {
                preferences.customPresets[index] = preset
                save()
            }
            renderMenu()
            applyManually()
        }
        panelModel.onAdjust = { [weak self] control, direction in self?.adjust(control, direction: direction) }
        panelModel.onPresetScale = { [weak self] id, percent in
            guard let self, !applying, !terminating,
                  let index = preferences.customPresets.firstIndex(where: { $0.id == id }),
                  let preset = preferences.customPresets[index].settingScale(percent) else { return }
            let isSelected = preferences.selectedCustomID == id
            preferences.customPresets[index] = preset
            if isSelected { adjustment = preset.adjustment }
            copySaved = false
            save()
        }
        panelModel.onSaveCopy = { [weak self] in self?.saveCopy() }
        panelModel.onApply = { [weak self] in self?.applyManually() }
        panelModel.onPreset = { [weak self] preset in
            guard let self else { return }
            copySaved = false
            preferences.preset = preset; preferences.selectedCustomID = nil; preferences.size = .standard
            copySaved = false
            adjustment = ResolutionAdjustment(preferences.dimensions); save(); applyManually()
        }
        panelModel.onCustom = { [weak self] id in
            guard let self, let custom = preferences.customPresets.first(where: { $0.id == id }) else { return }
            copySaved = false
            preferences.selectedCustomID = id; preferences.size = .standard
            adjustment = custom.adjustment; save(); applyManually()
        }
        panelModel.onSize = { [weak self] size in
            guard let self else { return }
            if let custom = preferences.selectedCustom, !CustomPreset.isSupported(custom.dimensions(size)) { return }
            preferences.size = size; adjustment = ResolutionAdjustment(preferences.dimensions); save(); applyManually()
        }
        panelModel.onSaveCustom = { [weak self] custom in
            guard let self, (try? custom.validate()) != nil else { return }
            // Settings save specifications; the toolbar applies them explicitly.
            if let index = preferences.customPresets.firstIndex(where: { $0.id == custom.id }) {
                preferences.customPresets[index] = custom
            } else { preferences.customPresets.append(custom) }
            copySaved = false
            if preferences.selectedCustomID == custom.id {
                preferences.size = .standard
                adjustment = custom.adjustment
            }
            save()
        }
        panelModel.onDeleteCustom = { [weak self] id in
            guard let self else { return }
            preferences.customPresets.removeAll { $0.id == id }
            for index in preferences.remoteDevices.indices where preferences.remoteDevices[index].presetID == id {
                preferences.remoteDevices[index].presetID = nil
            }
            if preferences.autoResolutionPresetID == id {
                preferences.autoResolutionPresetID = nil
            }
            if preferences.selectedCustomID == id { preferences.selectedCustomID = nil; adjustment = ResolutionAdjustment(preferences.dimensions) }
            save()
        }
        panelModel.onRecover = { [weak self] in self?.recover() }
        panelModel.onQuit = { [weak self] in self?.quit() }
        panelModel.onDetails = { [weak self] in self?.showDetails() }
        panelModel.onSettings = { [weak self] in self?.showSettings(page: .resolution) }
        panelModel.onNewCustom = { [weak self] in self?.showSettings(createNew: true) }
        panelModel.onIdentifyHintAction = { [weak self] action in self?.handleIdentifyHintAction(action) }

    }

    /// UU one-finger drags scroll; needs Accessibility, so retry quietly until granted.
    private func startTouchScroll() {
        guard preferences.uuTouchScrollEnabled, remoteStability.isConnected, !terminating else {
            touchScrollRetry?.invalidate(); touchScrollRetry = nil
            touchScroll.stop()
            return
        }
        let trusted = AXIsProcessTrusted()
        if trusted, touchScroll.start() { touchScrollRetry?.invalidate(); touchScrollRetry = nil; return }
        if !trusted {
            OperationDiagnostics.write("uu-touch-scroll-waiting-accessibility")
        }
        guard touchScrollRetry == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryTouchScroll() }
        }
        touchScrollRetry = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func retryTouchScroll() {
        guard !terminating, preferences.uuTouchScrollEnabled, remoteStability.isConnected, AXIsProcessTrusted(), touchScroll.start() else { return }
        touchScrollRetry?.invalidate(); touchScrollRetry = nil
    }

    /// Source-filtered wheel scaling also works when connection automation is disabled.
    /// Keep the watchdog off at original speed. It retries authorization and notices
    /// the standalone companion starting/stopping, without polling processes on the tap thread.
    private func startNativeScroll() {
        nativeScrollTimer?.invalidate(); nativeScrollTimer = nil
        refreshNativeScroll()
        guard preferences.uuScrollSpeedPercent < 100, !terminating else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNativeScroll() }
        }
        nativeScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshNativeScroll() {
        let enabled = preferences.uuScrollSpeedPercent < 100 && !terminating
        let companion = enabled && NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == UUNativeScroll.companionBundleID
        }
        guard enabled, !companion, AXIsProcessTrusted() else {
            nativeScroll.stop()
            return
        }
        nativeScroll.setPercent(preferences.uuScrollSpeedPercent)
        if !nativeScroll.start() { nativeScroll.stop() }
    }

    private func performWindowAction(_ action: FloatingAction) {
        guard let screen = floatingSwitcher.actionScreen else { return }
        let pid = floatingSwitcher.targetApplicationPID()
        let perform = { [weak self] in
            guard let self else { return }
            let previous = windowActionTask
            windowActionGeneration += 1
            let generation = windowActionGeneration
            windowActionTask = Task { @MainActor [weak self] in
                if let previous { await previous.value }
                guard let self, !terminating else { return }
                await workspaceLayout.suspendCurrentAdjustment()
                let area = workspaceLayout.region()?.area
                do { try await windowController.perform(action, targetPID: pid, screen: screen, workspace: area) }
                catch {
                    if !terminating, !(error is CancellationError) {
                        showNotice(error.localizedDescription, on: screen)
                    }
                }
                if generation == windowActionGeneration { windowActionTask = nil }
            }
        }
        if AXIsProcessTrusted() { perform() }
        else { ShortcutPermissions.shared.prepare(perform) }
    }

    /// Traffic-light group: act on the frontmost app's window via Accessibility, never via shortcuts.
    /// Test hook, off unless `defaults write <bundle id> BRDebugHooks -bool true`:
    /// a distributed notification "com.betterremote.debug.window" whose object is
    /// "snap:fill", "arrange:halves", "control:minimize" … runs the same code path as the buttons.
    private func installWindowDebugHook() {
        guard UserDefaults.standard.bool(forKey: "BRDebugHooks") else { return }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.betterremote.debug.window"), object: nil, queue: .main) { [weak self] note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let self else { return }
                let parts = command.split(separator: ":").map(String.init)
                OperationDiagnostics.write("debug-hook command=\(command) trusted=\(AXIsProcessTrusted()) target=\(self.windowControlTargetPID().map(String.init) ?? "nil")")
                guard parts.count == 2 else { return }
                switch parts[0] {
                case "snap": WindowSnap(rawValue: parts[1]).map { self.performWindowSnap($0) }
                case "arrange": WindowArrangement(rawValue: parts[1]).map { self.performArrange($0) }
                case "control": WindowControl(rawValue: parts[1]).map { self.performWindowControl($0) } // close / minimize / fullScreen
                default: break
                }
            }
        }
    }

    private func performWindowControl(_ control: WindowControl) {
        let screen = floatingSwitcher.actionScreen
        let perform = { [weak self] in
            guard let self else { return }
            // Only the frontmost app: never fall back to another app's window for close/minimize.
            guard let pid = windowControlTargetPID() else {
                showNotice("没有可操作的窗口", on: screen); return
            }
            Task { @MainActor [weak self] in
                do { if let message = try await WindowControlPerformer.perform(control, pid: pid) { self?.showNotice(message, on: screen) } }
                catch { self?.showNotice(error.localizedDescription, on: screen) }
            }
        }
        if AXIsProcessTrusted() { perform() }
        else { ShortcutPermissions.shared.prepare(perform) }
    }

    /// 清理桌面: minimizes every window on the current desktop, ours included (never the toolbar).
    private func performShowDesktop() {
        let screen = floatingSwitcher.actionScreen
        let perform = { [weak self] in
            guard let self else { return }
            let own = ProcessInfo.processInfo.processIdentifier
            let pids = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated }
                .map(\.processIdentifier)
            var ownCount = 0
            for window in NSApp.windows where WindowControlPerformer.isRealWindow(window) && window.isVisible
                && !window.isMiniaturized && window.styleMask.contains(.miniaturizable) && !window.styleMask.contains(.fullScreen) {
                window.miniaturize(nil); ownCount += 1
            }
            Task { @MainActor [weak self] in
                let result = await WindowAXWorker.shared.minimizeAll(pids: pids)
                OperationDiagnostics.write("show-desktop minimized=\(result.minimized + ownCount) failed=\(result.failed)")
                if result.minimized + ownCount == 0 { self?.showNotice(result.failed > 0 ? "窗口未能最小化" : "桌面上没有可收起的窗口", on: screen) }
            }
        }
        if AXIsProcessTrusted() { perform() }
        else { ShortcutPermissions.shared.prepare(perform) }
    }

    /// Frontmost app; when that is Better Remote itself, its own real window (e.g. Settings), never the toolbar.
    private func windowControlTargetPID() -> pid_t? {
        let own = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if front == own { return WindowControlPerformer.ownTarget() != nil ? own : floatingSwitcher.targetApplicationPID() }
        return front ?? floatingSwitcher.targetApplicationPID()
    }

    /// Toolbar 铺满 / 还原. The 布局 panel's 填充 keeps using `performWindowSnap(.fill)`.
    private func performFillToggle() {
        let screen = floatingSwitcher.actionScreen
        let perform = { [weak self] in
            guard let self else { return }
            guard let pid = windowControlTargetPID() else { showNotice("没有可操作的窗口", on: screen); return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await workspaceLayout.suspendCurrentAdjustment()
                do { try await WindowControlPerformer.toggleFill(pid: pid) }
                catch { self.showNotice(error.localizedDescription, on: screen) }
                self.floatingSwitcher.refreshFillState(after: 0.35)
            }
        }
        if AXIsProcessTrusted() { perform() } else { ShortcutPermissions.shared.prepare(perform) }
    }

    private func performWindowSnap(_ snap: WindowSnap) {
        let screen = floatingSwitcher.actionScreen
        let perform = { [weak self] in
            guard let self else { return }
            guard let pid = windowControlTargetPID() else { showNotice("没有可操作的窗口", on: screen); return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await workspaceLayout.suspendCurrentAdjustment()
                do { try await WindowControlPerformer.snap(snap, pid: pid) }
                catch { self.showNotice(error.localizedDescription, on: screen) }
            }
        }
        if AXIsProcessTrusted() { perform() } else { ShortcutPermissions.shared.prepare(perform) }
    }

    private func performArrange(_ arrangement: WindowArrangement) {
        let screen = floatingSwitcher.actionScreen
        let perform = { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else { showNotice("需要辅助功能权限才能排列窗口", on: screen); return }
            arrangementTask?.cancel()
            WindowPicker.shared.end()
            arrangementTask = Task { @MainActor [weak self] in
                guard let self, !terminating, !Task.isCancelled else { return }
                let pickGeneration = WindowControlPerformer.beginPicked()
                let pid = windowControlTargetPID()
                let front = if let pid { await WindowControlPerformer.frontScreenWindow(pid: pid) } else { nil as ScreenWindow? }
                guard !terminating, !Task.isCancelled else { return }
                if let front { WindowControlPerformer.placePicked(arrangement, window: front, slot: 0) }
                let started = WindowPicker.shared.begin(arrangement, prepicked: front, place: { window, slot in
                    WindowControlPerformer.placePicked(arrangement, window: window, slot: slot)
                }, finished: { [weak self] in
                    Task { @MainActor in
                        if let message = await WindowControlPerformer.endPicked(arrangement, generation: pickGeneration) { self?.showNotice(message, on: screen) }
                    }
                })
                if !started {
                    if let message = await WindowControlPerformer.endPicked(arrangement, generation: pickGeneration) { showNotice(message, on: screen) }
                }
            }
        }
        if AXIsProcessTrusted() { perform() } else { ShortcutPermissions.shared.prepare(perform) }
    }

    private func showNotice(_ title: String, detail: String? = nil, on screen: NSScreen? = nil) {
        guard let screen = screen ?? floatingSwitcher.actionScreen ?? NSScreen.main else { return }
        let area = floatingSwitcher.actionScreen == screen
            ? DesktopToolbarLayout.workspace(presence: floatingSwitcher.presence, toolbar: floatingSwitcher.reservedToolbarFrame,
                                             in: screen.visibleFrame, side: preferences.toolbarSide)
            : screen.visibleFrame
        notice.show(title, detail: detail, in: area)
    }
    /// Menu bar artwork from the bundle as template images (adapt to light / dark menu bars):
    /// normal, and active while a resolution is applied. Falls back to the previous SF Symbols.
    private static func templateImage(_ name: String) -> NSImage? {
        guard let image = Bundle.main.image(forResource: name) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Better Remote"
        return image
    }
    private static let menuBarTemplate = templateImage("MenuBarTemplate")
    private static let menuBarTemplateActive = templateImage("MenuBarTemplateActive")
    private static func statusImage(active: Bool) -> NSImage? {
        (active ? menuBarTemplateActive : menuBarTemplate)
            ?? NSImage(systemSymbolName: active ? "display.2" : "display", accessibilityDescription: "Better Remote")
    }
    @objc private func openSettings() { showSettings() }
    // The checkmark shows the real toolbar state, so a click flips what is on screen (also when automation opened it).
    @objc private func toggleFloating() { panelModel.onFloatingToggle(!floatingSwitcher.isVisible) }
    private func dismissToolPanels() {
        appLauncher.hide()
        resolutionWindow?.orderOut(nil)
        floatingSwitcher.setActivePanel(nil)
    }
    private func showApplications() {
        if appLauncher.isVisible { dismissToolPanels(); return }
        guard let screen = floatingSwitcher.actionScreen else { return }
        dismissToolPanels()
        settingsWindow?.orderOut(nil)
        appLauncher.show(anchor: floatingSwitcher.toolbarFrame, screen: screen, side: preferences.toolbarSide)
        floatingSwitcher.setActivePanel(.runningApplications)
    }
    private func showResolution() {
        if resolutionWindow?.isVisible == true { dismissToolPanels(); return }
        guard let screen = floatingSwitcher.actionScreen else { return }
        dismissToolPanels()
        settingsWindow?.orderOut(nil)
        let frame = resolutionPanelFrame(in: screen)
        let overlay = (resolutionWindow as? OverlayFloatingPanel) ?? OverlayFloatingPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.title = "Better Remote 分辨率"
        overlay.backgroundColor = .clear
        overlay.level = .floating
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = makeResolutionContent()
        resolutionWindow = overlay
        // Until the first content measurement arrives the panel would show at full height;
        // keep that first frame transparent (with a short fallback) instead of flashing it.
        if resolutionContentHeight == nil {
            overlay.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak overlay] in overlay?.alphaValue = 1 }
        } else {
            overlay.alphaValue = 1
        }
        overlay.setFrame(frame, display: true)
        overlay.makeKeyAndOrderFront(nil)
        (overlay.contentView as? NativeGlassView)?.attach(to: preferences.toolbarSide)
        (overlay.contentView as? NativeGlassView)?.reveal(from: preferences.toolbarSide)
        floatingSwitcher.setActivePanel(.resolution)
    }
    private func resolutionPanelFrame(in screen: NSScreen) -> CGRect {
        // Full edge height on every dock, like the 应用面板; content scrolls inside.
        DesktopToolbarLayout.resolutionPanel(to: floatingSwitcher.toolbarFrame, in: screen.visibleFrame, side: preferences.toolbarSide, presetCount: preferences.customPresets.count)
    }
    private func resolutionContentHeightChanged(_ height: CGFloat) {
        guard abs((resolutionContentHeight ?? 0) - height) > 0.5 else { return }
        resolutionContentHeight = height
        // The first measurement arrives after the panel is built at full height; resize it and
        // rebuild the glass host at the fitted size so its layers follow the new frame.
        guard let window = resolutionWindow, let screen = window.screen ?? floatingSwitcher.actionScreen else { return }
        let frame = resolutionPanelFrame(in: screen)
        guard window.frame != frame else { window.alphaValue = 1; return }
        window.setFrame(frame, display: false)
        window.contentView = makeResolutionContent()
        (window.contentView as? NativeGlassView)?.attach(to: preferences.toolbarSide)
        window.display()
        window.alphaValue = 1
    }
    private func makeResolutionContent() -> NSView {
        glassHost(ResolutionPanelView(model: panelModel, close: { [weak self] in self?.dismissToolPanels() }, restore: { [weak self] in self?.dismissToolPanels(); self?.recover() }, onContentHeight: { [weak self] height in
            DispatchQueue.main.async { self?.resolutionContentHeightChanged(height) }
        }), cornerRadius: DesignTokens.radiusXl)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    private func showSettings(createNew: Bool = false, page: SettingsPage? = nil) {
        dismissToolPanels()
        let window = settingsWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                                                styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        let destination = createNew ? .resolution : (page ?? .resolution)
        let content = SettingsView(model: panelModel, startNew: createNew, page: destination)
        if settingsWindow == nil || createNew || page != nil {
            let host = NSHostingController(rootView: content)
            // The window size comes from fitSettingsWindow, not from the SwiftUI ideal size.
            host.sizingOptions = []
            window.contentViewController = host
        }
        if settingsWindow == nil { window.setContentSize(SettingsWindowLayout.preferredSize); window.center() }
        window.title = "设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.remove(.resizable)
        window.setFrameAutosaveName("RemoteFit.Settings")
        settingsWindow = window
        fitSettingsWindow()
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if settingsDragScroll == nil { settingsDragScroll = WindowDragScroll(window: window) }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    /// 设置 is fixed at 900 × 720 on a normal desktop; on a narrow or short screen it shrinks to
    /// the visible area (with margins) and moves fully on screen. Not user-resizable.
    private func fitSettingsWindow() {
        guard let window = settingsWindow, let screen = window.screen ?? NSScreen.main else { return }
        let preferred = SettingsWindowLayout.preferredSize
        let reference = window.frameRect(forContentRect: NSRect(origin: .zero, size: preferred))
        let chrome = CGSize(width: reference.width - preferred.width, height: reference.height - preferred.height)
        // An expanded toolbar floats above 设置; keep the window (and its sheets) beside it, in the
        // same area 铺满 uses (the visible frame minus the toolbar only while it is docked and expanded).
        let area = SettingsWindowLayout.spacedFromToolbar(WindowControlPerformer.layoutArea(screen),
                                                          visible: screen.visibleFrame, side: preferences.toolbarSide)
        DialogLimit.settingsArea = area
        let target = SettingsWindowLayout.clampedFrame(window.frame, in: area, chrome: chrome)
        let contentSize = window.contentRect(forFrameRect: target).size
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        if window.frame != target {
            window.setFrame(target, display: window.isVisible)
            OperationDiagnostics.write("settings_window_fit size=\(Int(target.width))x\(Int(target.height)) visible=\(Int(screen.visibleFrame.width))x\(Int(screen.visibleFrame.height)) area=\(Int(area.width))x\(Int(area.height))")
        }
    }
    func renderMenu() {
        let trusted = AXIsProcessTrusted()
        let workspaceEnabled = floatingSwitcher.isExpanded && !applying && !terminating && trusted
        workspaceLayout.setEnabled(workspaceEnabled)
        // The Dock change (and its re-fit) lands first, so auto-fill uses the final visible area.
        autoFill.setEnabled(preferences.autoFillWindowsOnRemote && toolbarPresence.context == .connected && !terminating && trusted
                            && connectionDockTask == nil)
        if panelModel.copySaved != copySaved { panelModel.copySaved = copySaved }
        if panelModel.adjustment != adjustment { panelModel.adjustment = adjustment }
        item?.button?.toolTip = "Better Remote · \(status.title)"
        item?.button?.image = Self.statusImage(active: status.active)
        if panelModel.preferences != preferences { panelModel.preferences = preferences }
        if panelModel.status != status.title { panelModel.status = status.title }
        if panelModel.detail != status.detail { panelModel.detail = status.detail }
        if panelModel.statusActive != status.active { panelModel.statusActive = status.active }
        if panelModel.terminating != terminating { panelModel.terminating = terminating }
        if panelModel.applying != applying { panelModel.applying = applying }
        if panelModel.applied != status.applied { panelModel.applied = status.applied }
        updateToolbarMenuState()
        // The toolbar may expand or collapse (e.g. once a connection's resolution is applied).
        if settingsWindow?.isVisible == true { fitSettingsWindow() }
        item?.menu?.item(withTag: 2)?.isEnabled = !applying && !terminating
        if appLauncher.isVisible, let screen = floatingSwitcher.actionScreen {
            appLauncher.update(anchor: floatingSwitcher.toolbarFrame, screen: screen, side: preferences.toolbarSide)
        }
        if let window = resolutionWindow, window.isVisible, let screen = window.screen ?? NSScreen.main {
            let frame = resolutionPanelFrame(in: screen)
            if window.frame != frame { window.setFrame(frame, display: true) }
        }
    }
    /// 显示工具条 is checked exactly when the toolbar panel is on screen, however it got there
    /// (manual toggle, connect automation, disconnect automation, launch, termination).
    private func updateToolbarMenuState() {
        item?.menu?.item(withTag: 1)?.state = floatingSwitcher.isVisible ? .on : .off
    }
    func menuNeedsUpdate(_ menu: NSMenu) { updateToolbarMenuState() }
    private func adjust(_ control: ResolutionAdjustment.Control, direction: Int) {
        guard !applying, !terminating, let next = adjustment.stepping(control, direction: direction) else { return }
        copySaved = false
        adjustment = next
        if control == .scale, let id = preferences.selectedCustomID,
           let index = preferences.customPresets.firstIndex(where: { $0.id == id }),
           let preset = preferences.customPresets[index].settingScale(next.scalePercent) {
            preferences.customPresets[index] = preset
            save()
        }
        renderMenu()
        applyManually(dismissPanel: false)
    }
    private func saveCopy() {
        guard !applying, !terminating, status.applied == adjustment.dimensions else { return }
        let copy = adjustment.copyPreset()
        var next = preferences
        next.customPresets.append(copy)
        next.selectedCustomID = copy.id; next.size = .standard
        do {
            try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
            preferences = next
            adjustment = ResolutionAdjustment(copy.dimensions(.standard))
            status.title = "副本已保存"
            copySaved = true
        } catch { status.detail = error.localizedDescription; status.title = "保存失败" }
        renderMenu()
    }
    private func applyManually(dismissPanel: Bool = true) {
        guard !applying, !terminating else { return }
        automaticPolicy.manualAdjustment()
        if !automaticPolicy.ownsResolution { automaticRestorePoint = nil }
        applyGeneration += 1
        let generation = applyGeneration
        applying = true
        status = .init(title: "正在应用…", active: status.active, applied: status.applied)
        renderMenu()
        Task { [weak self] in
            guard let self else { return }
            guard generation == self.applyGeneration, !self.terminating else { return }
            let result = await self.engine.apply(self.adjustment.dimensions)
            guard generation == self.applyGeneration else { return }
            self.status = result
            if dismissPanel, result.detail == nil {
                self.dismissToolPanels()
            }
            self.applying = false
            self.floatingSwitcher.redock()
            runAutomaticResolutionIfNeeded()
            self.renderMenu()
        }
    }
    @objc private func recover() {
        guard !applying, !terminating else { return }
        automaticPolicy.manualOverride()
        automaticRestorePoint = nil
        applyGeneration += 1
        let generation = applyGeneration
        applying = true; renderMenu()
        Task {
            await engine.log("manual_restore_start")
            guard generation == applyGeneration, !terminating else { return }
            do {
                if try await engine.restore() { status = .init(title: "已还原屏幕") }
                else { status = await engine.report("显示器接回后自动还原") }
            }
            catch { status = .init(title: "还原未完成", detail: error.localizedDescription) }
            applying = false; renderMenu(); floatingSwitcher.redock(); runAutomaticResolutionIfNeeded()
        }
    }
    private func saveAutomaticPreferences(_ next: Preferences) {
        do {
            try JSONEncoder().encode(next).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
            let wasReady = preferences.autoResolutionEnabled
            let isReady = next.autoResolutionEnabled
            let monitoringChanged = preferences.needsRemoteConnectionMonitoring != next.needsRemoteConnectionMonitoring
            let dockModeChanged = preferences.connectionDockMode != next.connectionDockMode
            let toolbarChanged = ToolbarPresence.shows(toolbarPresence.context, preferences: preferences)
                != ToolbarPresence.shows(toolbarPresence.context, preferences: next)
            preferences = next
            connectionToolbarPolicy.setEnabled(next.toolbarWhenConnected)
            if toolbarChanged {
                // Flipping the switch for the current state takes effect now (and replaces any queued expansion).
                _ = connectionToolbarPolicy.takeAction(busy: false)
                applyToolbarSetting()
            }
            if wasReady != isReady {
                automaticPolicy = AutomaticResolutionPolicy()
                automaticPolicy.setEnabled(isReady)
                automaticPolicy.connectionChanged(remoteStability.isConnected)
            }
            automaticPolicy.setEnabled(isReady)
            automaticPolicy.restoreOnDisconnect = next.autoRestoreOnDisconnect
            connectionDockPolicy.setEnabled(next.connectionDockMode != .keep)
            // Changing the mode mid-session takes effect now; 保持现状 gives back anything still owed.
            if dockModeChanged, remoteStability.isConnected || dockSession.owesRestore { syncConnectionDock() }
            if !next.autoResolutionEnabled { automaticRestorePoint = nil }
            if monitoringChanged {
                startRemoteMonitor()
            }
            renderMenu()
            runAutomaticResolutionIfNeeded()
        } catch { showNotice("设置保存失败", detail: error.localizedDescription) }
    }

    private func startRemoteMonitor() {
        remoteMonitor.stop()
        remoteStability = RemoteSessionStability()
        remoteDeviceID = nil
        lastMatchedDeviceID = nil
        // Detection restarts from scratch; a session that is still there reconfirms within the 5 s grace.
        remoteToolbarTransition(connected: false)
        connectionToolbarPolicy.setEnabled(preferences.toolbarWhenConnected)
        startTouchScroll()
        // UU device collection remains active even when screen automation is disabled.
        guard !terminating else { return }
        remoteMonitor.start { [weak self] in
            guard let self else { return nil }
            let snapshot = await remoteProbe.sample(identifyUU: true)
            guard !Task.isCancelled, !terminating else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            if !snapshot.active.isEmpty || remoteStability.isConnected {
                // Earliest remote evidence: nothing seen from here until restore + settle is a user choice.
                stableModeTask?.cancel(); stableModeTask = nil
                Task { [engine] in await engine.noteRemoteActivity() }
            }
            if !snapshot.active.contains(.uu), !snapshot.unknown.contains(.uu) { deviceCollection.disconnected() }
            let oldDeviceID = lastMatchedDeviceID
            // Other providers never inherit a UU-specific rule.
            remoteDeviceID = snapshot.active == [.uu] ? snapshot.uuDevice?.id : nil
            if let transition = remoteStability.observe(snapshot, at: now) {
                if transition == .disconnected {
                    lastMatchedDeviceID = nil
                    panelModel.identifyHint = nil
                }
                automaticPolicy.connectionChanged(transition == .connected)
                connectionDockPolicy.connectionChanged(transition == .connected)
                remoteToolbarTransition(connected: transition == .connected)
                if transition == .disconnected { syncConnectionDock() }
                startTouchScroll()
                let providers = snapshot.active.map(\.rawValue).sorted().joined(separator: ",")
                Task { [engine] in await engine.log("remote_signal", "\(transition) providers=\(providers) uptime=\(now)") }
            }
            // Include nil → device so a late identify (after connect) still auto-applies.
            if preferences.deviceResolutionEnabled, oldDeviceID != remoteDeviceID, remoteDeviceID != nil {
                automaticPolicy.controllerChanged()
            }
            if let remoteDeviceID { lastMatchedDeviceID = remoteDeviceID }
            if let device = snapshot.uuDevice {
                var next = preferences
                deviceCollection.remember(device, in: &next)
                if next != preferences { saveAutomaticPreferences(next) }
            }
            updateIdentifyHint(from: snapshot)
            runAutomaticResolutionIfNeeded()
            return snapshot.confirmationDelay(remoteStability.confirmationDelay(at: now))
        }
    }

    private func updateIdentifyHint(from snapshot: RemoteSessionSnapshot) {
        let device = snapshot.uuDevice
        let deviceHasPreset: Bool = {
            guard let id = device?.id,
                  let presetID = preferences.remoteDevices.first(where: { $0.id == id })?.presetID,
                  preferences.customPresets.contains(where: { $0.id == presetID }) else { return false }
            return true
        }()
        let hasDefault = preferences.customPresets.contains { $0.id == preferences.autoResolutionPresetID }
        let hint = UUIdentifyHintBuilder.build(
            status: snapshot.uuIdentifyStatus,
            device: device,
            deviceHasPreset: deviceHasPreset,
            defaultResolutionEnabled: preferences.defaultResolutionEnabled,
            hasDefaultPreset: hasDefault,
            exhausted: snapshot.uuIdentifyExhausted,
            deviceResolutionEnabled: preferences.deviceResolutionEnabled
        )
        if panelModel.identifyHint != hint { panelModel.identifyHint = hint }
    }

    private func handleIdentifyHintAction(_ action: UUIdentifyHint.Action) {
        switch action {
        case .openAccessibility:
            ShortcutPermissions.shared.showGuide()
        case .retry:
            Task { [remoteProbe] in
                await remoteProbe.retryUUIdentify()
            }
            // Connected UU keeps recheckAfter=1; next sample will identify again.
        case .openSettings:
            showSettings(page: .connection)
        }
    }

    /// A monitor came back after a headless session: finish the deferred restore,
    /// but only while nobody is remoting in.
    private var stableModeTask: Task<Void, Never>?
    /// Event-driven: every display change restarts a 10 s quiet window; modes unchanged across it
    /// are recorded, but only while idle (no remote session, no apply/restore in progress).
    private func scheduleStableModeRecord() {
        stableModeTask?.cancel()
        stableModeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let the change land before taking the baseline, then require 10 s of no change.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await engine.beginStableWindow()
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, !applying, !terminating, !remoteStability.isConnected else { return }
            await engine.finishStableWindow()
        }
    }
    private func resumePendingRestoreIfPossible() {
        guard !applying, !terminating, !remoteStability.isConnected else { return }
        Task { @MainActor [weak self] in
            guard let self, await engine.isRestorePending() else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !applying, !terminating, !remoteStability.isConnected else { return }
            applying = true; renderMenu()
            let done = await engine.resumePendingRestore()
            applying = false
            if done {
                await engine.log("deferred_restore_complete")
                status = .init(title: "已还原屏幕")
                if automaticRestorePoint != nil { restoreAutomaticSelection(); automaticRestorePoint = nil; save() }
                floatingSwitcher.redock()
            }
            renderMenu()
        }
    }

    private func runAutomaticResolutionIfNeeded() {
        if !terminating, connectionDockPolicy.takeAction(busy: applying) { syncConnectionDock() }
        guard let action = automaticPolicy.nextAction(busy: applying || terminating) else {
            runPendingToolbarExpansion()
            return
        }
        switch action {
        case .apply:
            guard let preset = preferences.automaticPreset(for: remoteDeviceID) else {
                automaticPolicy.applied(success: false)
                runPendingToolbarExpansion()
                return
            }
            if automaticRestorePoint == nil {
                automaticRestorePoint = .init(preset: preferences.preset, size: preferences.size,
                    selectedCustomID: preferences.selectedCustomID, adjustment: adjustment)
            }
            let dimensions = preset.dimensions(.standard)
            // Already on the default (resolution kept from the last connection): nothing to switch.
            if status.detail == nil, status.applied == dimensions, preferences.selectedCustomID == preset.id {
                Task { [engine] in await engine.log("automatic_apply_skipped", dimensions.label) }
                automaticPolicy.applied(success: true)
                renderMenu()
                runPendingToolbarExpansion()
                return
            }
            preferences.selectedCustomID = preset.id
            preferences.size = .standard
            adjustment = preset.adjustment
            copySaved = false
            applying = true
            status.title = "正在自动切换…"
            renderMenu()
            let generation = applyGeneration
            Task { @MainActor [weak self] in
                guard let self else { return }
                await engine.log("automatic_apply_start", dimensions.label)
                let result = await engine.apply(dimensions)
                await engine.log("automatic_apply_result", result.detail == nil ? "success" : "failed")
                guard !terminating, generation == applyGeneration else { return }
                status = result
                applying = false
                floatingSwitcher.redock()
                let success = result.detail == nil && result.applied == dimensions
                automaticPolicy.applied(success: success)
                if !success {
                    restoreAutomaticSelection()
                    automaticRestorePoint = nil
                    showNotice("自动切换未完成", detail: result.detail)
                }
                renderMenu()
                runAutomaticResolutionIfNeeded()
            }
        case .restore:
            applying = true
            status.title = "正在还原屏幕…"
            renderMenu()
            let generation = applyGeneration
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result: EngineStatus
                var deferred = false
                await engine.log("automatic_restore_start", "physical_displays")
                do {
                    if try await engine.restore() {
                        await engine.log("automatic_restore_complete", "physical_displays")
                        result = .init(title: "已还原屏幕")
                    } else {
                        // Headless: keep the current virtual display; restore when a monitor returns.
                        deferred = true
                        result = await engine.report("显示器接回后自动还原")
                    }
                } catch {
                    await engine.log("automatic_restore_failed", error.localizedDescription)
                    result = .init(title: "还原未完成", detail: error.localizedDescription)
                }
                guard !terminating, generation == applyGeneration else { return }
                status = result
                applying = false
                floatingSwitcher.redock()
                let success = result.detail == nil
                automaticPolicy.restored(success: success)
                if success && !deferred {
                    restoreAutomaticSelection()
                    automaticRestorePoint = nil
                    save()
                } else { showNotice("自动还原未完成", detail: result.detail) }
                renderMenu()
                runAutomaticResolutionIfNeeded()
            }
        }
    }

    /// Bring the Dock's 自动隐藏 in line with 连接时的程序坞: the chosen mode while connected, the user's own value
    /// otherwise. Runs off the main thread (the first use may wait on the 系统事件 permission prompt) and never
    /// holds up resolution or toolbar work. Overlapping requests coalesce into one more pass.
    private func syncConnectionDock() {
        guard !terminating else { return }
        if connectionDockTask != nil { connectionDockSyncAgain = true; return }
        // Nothing to do (保持现状 and nothing owed): don't start a task, which would pause auto-fill.
        guard dockSession.needsDock(for: remoteStability.isConnected ? preferences.connectionDockMode : .keep) else { return }
        connectionDockTask = Task { @MainActor [weak self] in
            guard let self else { return }
            renderMenu() // holds auto-fill until the Dock work is done
            repeat {
                connectionDockSyncAgain = false
                await performConnectionDockSync()
            } while connectionDockSyncAgain && !terminating && !Task.isCancelled
            if !Task.isCancelled { connectionDockTask = nil; renderMenu() }
        }
    }

    private func performConnectionDockSync() async {
        let mode = remoteStability.isConnected ? preferences.connectionDockMode : .keep
        guard dockSession.needsDock(for: mode) else { return }
        let bridge = DockAutohideBridge.shared
        do {
            let current = try await bridge.read()
            guard !terminating else { return }
            var next = dockSession
            guard let value = next.apply(mode: mode, current: current) else {
                dockSession = next; DockAutohideBridge.persistedOriginal = next.originalAutohide
                return
            }
            // Remember the user's value before touching the Dock, so a crash mid-write can still restore it.
            if next.owesRestore { DockAutohideBridge.persistedOriginal = next.originalAutohide }
            let before = WindowControlPerformer.layoutAreas()
            do { try await bridge.write(value) }
            catch {
                if !terminating { DockAutohideBridge.persistedOriginal = dockSession.originalAutohide }
                throw error
            }
            guard !terminating else { return }
            dockSession = next; DockAutohideBridge.persistedOriginal = next.originalAutohide
            await engine.log("connection_dock", "mode=\(mode.rawValue) autohide \(current)->\(value)")
            // Wait (≤ 1 s) for the screens' visible frame to reflect the Dock, then move windows that were filling
            // the old area so none sits under an always-shown Dock (or stays short after it auto-hides).
            var areas = WindowControlPerformer.dockAreas(from: before)
            for _ in 0..<20 where !areas.contains(where: DockRefit.changed) {
                try? await Task.sleep(for: .milliseconds(50))
                guard !terminating else { return }
                areas = WindowControlPerformer.dockAreas(from: before)
            }
            if areas.contains(where: DockRefit.changed) {
                let moved = await WindowControlPerformer.refitFilledWindows(areas)
                await engine.log("connection_dock_refit", "moved=\(moved)")
            } else {
                await engine.log("connection_dock_refit", "visible_frame_unchanged")
            }
        } catch {
            await engine.log("connection_dock_failed", "mode=\(mode.rawValue) \(error.localizedDescription)")
            // Never fall back to the toggle shortcut: it flips the Dock the wrong way for always-shown Docks.
            if let error = error as? DockAutohideBridge.ScriptError, error.isPermissionDenied, !dockPermissionNoticeShown, !terminating {
                dockPermissionNoticeShown = true
                showNotice("程序坞设置未生效", detail: error.localizedDescription)
            }
        }
    }

    private func runPendingToolbarExpansion() {
        guard !terminating, toolbarPresence.context == .connected,
              connectionToolbarPolicy.takeAction(busy: applying) else { return }
        OperationDiagnostics.write("toolbar-auto-expand resolutionReady=true")
        floatingSwitcher.showExpanded()
        renderMenu()
    }

    /// ON = expanded bar, OFF = fully hidden (no ball), for the setting that applies right now.
    private func applyToolbarSetting() {
        guard !terminating else { return }
        if ToolbarPresence.shows(toolbarPresence.context, preferences: preferences) { floatingSwitcher.showExpanded() }
        else { floatingSwitcher.setEnabled(false) }
        renderMenu()
    }

    private func remoteToolbarTransition(connected: Bool) {
        if let context = toolbarPresence.remoteChanged(connected: connected, at: ProcessInfo.processInfo.systemUptime) {
            enterToolbarContext(context)
        }
        scheduleToolbarPresenceTick()
    }

    private func scheduleToolbarPresenceTick() {
        toolbarPresenceTimer?.invalidate(); toolbarPresenceTimer = nil
        guard !terminating, let delay = toolbarPresence.delayUntilTick(at: ProcessInfo.processInfo.systemUptime) else { return }
        let timer = Timer(timeInterval: delay + 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.toolbarPresenceTimer = nil
                if let context = self.toolbarPresence.tick(at: ProcessInfo.processInfo.systemUptime) { self.enterToolbarContext(context) }
                self.scheduleToolbarPresenceTick()
            }
        }
        toolbarPresenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func enterToolbarContext(_ context: ToolbarPresence.Context) {
        connectionToolbarPolicy.connectionChanged(context == .connected)
        // Connected + 远程连接时显示: the monitor's runAutomaticResolutionIfNeeded expands it once
        // connection-time display work has finished (runPendingToolbarExpansion).
        if context == .connected && preferences.toolbarWhenConnected { renderMenu() } else { applyToolbarSetting() }
    }

    private func restoreAutomaticSelection() {
        guard let point = automaticRestorePoint else { return }
        preferences.preset = point.preset
        preferences.size = point.size
        preferences.selectedCustomID = point.selectedCustomID
        adjustment = point.adjustment
        copySaved = false
    }

    @objc private func showDetails() {
        showNotice(status.title, detail: status.detail)
    }
    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
