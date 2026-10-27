import AppKit
import ApplicationServices
import SwiftUI
import RemoteFitCore

private final class PermissionGuidePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ShortcutPermissions: ObservableObject {
    static let shared = ShortcutPermissions()
    @Published private(set) var state = ShortcutPermissionState(accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
    var granted: Bool { state.granted }
    private var statusTimer: Timer?
    private var panel: NSPanel?
    private var timer: Timer?
    private var completion: (() -> Void)?
    private var started = Date.distantPast
    private init() {}
    func refresh() {
        let current = ShortcutPermissionState(accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess())
        if state != current { state = current }
    }
    func startMonitoring() {
        refresh()
        guard statusTimer == nil else { return }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common); statusTimer = timer
    }
    func stopMonitoring() { statusTimer?.invalidate(); statusTimer = nil }

    func prepare(_ onGranted: @escaping () -> Void) {
        refresh()
        guard !granted else {
            onGranted(); return
        }
        completion = onGranted
        showGuide()
    }
    func showGuide() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            return
        }
        closePanel(clearCompletion: false)
        let card = PermissionGuidePanel(contentRect: .init(x: 0, y: 0, width: 390, height: 80),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        card.level = .floating; card.isOpaque = false; card.backgroundColor = .clear
        card.hasShadow = true; card.hidesOnDeactivate = false; card.isReleasedWhenClosed = false
        card.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        card.contentView = NSHostingView(rootView: PermissionGuideView(close: { [weak self] in self?.closePanel() }))
        panel = card; started = Date()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    private func closePanel(clearCompletion: Bool = true) {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        if clearCompletion { completion = nil }
    }
    private func poll() {
        refresh()
        if granted {
            let callback = completion; closePanel()
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first { $0.title == "设置" }?.makeKeyAndOrderFront(nil)
            callback?(); return
        }
        guard Date().timeIntervalSince(started) < 180 else { closePanel(); return }
        guard let settings = NSWorkspace.shared.frontmostApplication,
              settings.bundleIdentifier == "com.apple.systempreferences" else { panel?.orderOut(nil); return }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let panel else { return }
        let frames = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == settings.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }.compactMap { item -> CGRect? in
            guard let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 320, frame.height > 240 else { return nil }
            return frame
        }
        guard let cgFrame = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else { panel.orderOut(nil); return }
        let pairs = NSScreen.screens.compactMap { screen -> (NSScreen, CGRect)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen, CGDisplayBounds(number.uint32Value))
        }
        guard let match = pairs.filter({ $0.1.intersects(cgFrame) }).max(by: { $0.1.intersection(cgFrame).width * $0.1.intersection(cgFrame).height < $1.1.intersection(cgFrame).width * $1.1.intersection(cgFrame).height }) else { return }
        let visible = match.0.visibleFrame
        let frame = CGRect(x: match.0.frame.minX + cgFrame.minX - match.1.minX,
                           y: match.0.frame.maxY - (cgFrame.minY - match.1.minY) - cgFrame.height,
                           width: cgFrame.width, height: cgFrame.height)
        let width = min(max(360, frame.width - 230), visible.width - 24)
        let x = min(max(frame.minX + 230, visible.minX + 12), visible.maxX - width - 12)
        let y = min(max(frame.minY, visible.minY + 12), visible.maxY - 92)
        panel.setFrame(.init(x: x, y: y, width: width, height: 80), display: true)
        if !panel.ignoresMouseEvents { panel.orderFrontRegardless() }
    }
}
private struct PermissionGuideView: View {
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up").foregroundStyle(Color.accentColor)
                Text("拖入辅助功能列表并开启").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 22) }
                    .buttonStyle(.plain).accessibilityLabel("关闭权限引导")
            }
            PermissionAppDragSource().frame(height: 38)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color.blue.opacity(0.16), Color.purple.opacity(0.12), Color.teal.opacity(0.14)], startPoint: .leading, endPoint: .trailing)))
        }
    }
}
private struct PermissionAppDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> PermissionDragView { PermissionDragView(frame: .zero) }
    func updateNSView(_ view: PermissionDragView, context: Context) {}
}
@MainActor
private final class PermissionDragView: NSView, NSDraggingSource {
    private var initial = NSPoint.zero
    private var dragging = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) { drawRow(in: bounds) }
    private func drawRow(in rect: NSRect) {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
        icon.draw(in: .init(x: rect.minX + 5, y: rect.midY - 13, width: 26, height: 26))
        ("Better Remote" as NSString).draw(at: .init(x: rect.minX + 39, y: rect.midY - 8),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
    }
    override func mouseDown(with event: NSEvent) { initial = convert(event.locationInWindow, from: nil); dragging = false }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !dragging, hypot(point.x - initial.x, point.y - initial.y) > 4 else { return }
        dragging = true
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        let size = NSSize(width: min(bounds.width, 230), height: 38)
        let preview = NSImage(size: size)
        preview.lockFocus(); drawRow(in: .init(origin: .zero, size: size)); preview.unlockFocus()
        item.setDraggingFrame(.init(x: point.x - min(initial.x, size.width), y: point.y - 19, width: size.width, height: size.height), contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { window?.ignoresMouseEvents = true; window?.alphaValue = 0.65; window?.orderBack(nil) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false; window?.ignoresMouseEvents = false; window?.alphaValue = 1; window?.orderFrontRegardless(); ShortcutPermissions.shared.refresh() }
}