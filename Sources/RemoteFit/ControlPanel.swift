import AppKit
import SwiftUI
import RemoteFitCore

final class OverlayFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct VisualEffectBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var cornerRadius: CGFloat = 18

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
    }
}

@MainActor
final class ControlPanelModel: ObservableObject {
    @Published var preferences = Preferences()
    @Published var connectedDeviceID: String?
    var onDeviceViewed: (String) -> Void = { _ in }
    var onDeviceName: (String, String) -> Void = { _, _ in }
    var onDeviceConfigurationEnabled: (String, Bool) -> Void = { _, _ in }
    var onDeviceConfiguration: (String?, DeviceConfiguration) -> Void = { _, _ in }
    @Published var status = "正在检测…"
    @Published var detail: String?
    @Published var identifyHint: UUIdentifyHint?
    @Published var statusActive = false
    @Published var terminating = false
    @Published var applying = false
    @Published var applied: Dimensions?
    @Published var copySaved = false
    @Published var adjustment = ResolutionAdjustment(Preferences().dimensions)
    var onAutoResolutionToggle: (Bool) -> Void = { _ in }
    var onDefaultResolutionToggle: (Bool) -> Void = { _ in }
    var onDeviceResolutionToggle: (Bool) -> Void = { _ in }
    var onDeleteRemoteDevice: (String) -> Void = { _ in }
    var onDeviceResolutionPreset: (String, String?) -> Void = { _, _ in }
    var onAutoResolutionPreset: (String) -> Void = { _ in }
    var onToolbarWhenConnectedToggle: (Bool) -> Void = { _ in }
    var onToolbarWhenDisconnectedToggle: (Bool) -> Void = { _ in }
    var onConnectionDockMode: (ConnectionDockMode) -> Void = { _ in }
    var onAutoFillWindowsToggle: (Bool) -> Void = { _ in }
    var onWindowControlsToggle: (Bool) -> Void = { _ in }
    var onUUTouchScrollToggle: (Bool) -> Void = { _ in }
    var onUUScrollSpeedPercent: (Int) -> Void = { _ in }
    var onAutoRestoreToggle: (Bool) -> Void = { _ in }
    var onScale: (Int) -> Void = { _ in }
    var onPresetScale: (String, Int) -> Void = { _, _ in }
    var onAdjust: (ResolutionAdjustment.Control, Int) -> Void = { _, _ in }
    var onSaveCopy: () -> Void = {}
    var onSaveApplicationShortcuts: ([ApplicationShortcuts], Bool) -> Bool = { _, _ in false }
    var onSaveShortcut: (NamedShortcut) -> Bool = { _ in false }
    var onDeleteShortcut: (String) -> Bool = { _ in false }
    var onShortcutToggle: (String, Bool) -> Void = { _, _ in }
    var onFloatingActionIcon: (FloatingAction, ShortcutIcon) -> Bool = { _, _ in false }
    var onFloatingActionToggle: (FloatingAction, Bool) -> Void = { _, _ in }
    var onMoveOperations: (IndexSet, Int) -> Void = { _, _ in }
    var onToolbarSide: (ToolbarSide) -> Void = { _ in }
    var onTheme: (AppTheme) -> Void = { _ in }
    var onFloatingToggle: (Bool) -> Void = { _ in }
    var onApply: () -> Void = {}
    var onPreset: (ScreenPreset) -> Void = { _ in }
    var onCustom: (String) -> Void = { _ in }
    var onSize: (DisplaySize) -> Void = { _ in }
    var onSaveCustom: (CustomPreset) -> Void = { _ in }
    var onDeleteCustom: (String) -> Void = { _ in }
    var onRecover: () -> Void = {}
    var onQuit: () -> Void = {}
    var onSettings: () -> Void = {}
    var onNewCustom: () -> Void = {}
    var onIdentifyHintAction: (UUIdentifyHint.Action) -> Void = { _ in }
}

struct ScreenGlyph: View {
    let dimensions: Dimensions
    var selected = false
    var maximumWidth: CGFloat = 34
    var maximumHeight: CGFloat = 22
    var strokeOpacity: Double = 0.2

    static func menuImage(dimensions: Dimensions) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 22), flipped: false) { _ in
            let scale = min(28 / Double(max(1, dimensions.width)), 18 / Double(max(1, dimensions.height)))
            let width = max(6, Double(dimensions.width) * scale)
            let height = max(6, Double(dimensions.height) * scale)
            let frame = NSRect(x: (32 - width) / 2, y: (22 - height) / 2, width: width, height: height)
            NSColor.labelColor.setStroke()
            let path = NSBezierPath(roundedRect: frame, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.3
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    var body: some View {
        let scale = min(maximumWidth / Double(max(1, dimensions.width)), maximumHeight / Double(max(1, dimensions.height)))
        let w = max(12, Double(dimensions.width) * scale)
        let h = max(12, Double(dimensions.height) * scale)

        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(selected ? DesignTokens.Colors.accent.opacity(0.16) : Color.primary.opacity(0.04))
            RoundedRectangle(cornerRadius: 2.5)
                .stroke(selected ? DesignTokens.Colors.accent : Color.primary.opacity(strokeOpacity), lineWidth: selected ? 1.2 : 0.8)
        }
        .frame(width: w, height: h)
        .frame(width: maximumWidth + 2, height: maximumHeight + 2)
        .accessibilityHidden(true)
    }
}
