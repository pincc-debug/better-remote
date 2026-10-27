import AppKit
import SwiftUI
import RemoteFitCore

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var key: ShortcutKey?
    func makeNSView(context: Context) -> ShortcutCaptureView { ShortcutCaptureView() }
    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.savedLabel = key?.label ?? "录制快捷键"
        view.onCapture = { key = $0 }
        view.needsDisplay = true
    }
}
@MainActor
final class ShortcutCaptureView: NSView {
    var savedLabel = "录制快捷键"
    var onCapture: (ShortcutKey) -> Void = { _ in }
    private var recording = false
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var downKeys = Set<UInt16>()
    private var modifierCandidate: ShortcutKey?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        ShortcutPermissions.shared.prepare { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
            recording = true; modifierCandidate = nil; downKeys.removeAll()
            startTap(); needsDisplay = true
        }
    }
    override func resignFirstResponder() -> Bool { recording = false; stopTap(); needsDisplay = true; return true }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopTap(); recording = false }
        super.viewWillMove(toWindow: newWindow)
    }
    private func startTap() {
        stopTap()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let view = Unmanaged<ShortcutCaptureView>.fromOpaque(pointer).takeUnretainedValue()
            let suppress = MainActor.assumeIsolated { view.intercept(type, event) }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            recording = false; savedLabel = "无法录制，请手动选择"; return
        }
        eventTap = tap
        eventSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let eventSource { CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    private func stopTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopSourceInvalidate(eventSource) }
        eventTap = nil; eventSource = nil; downKeys.removeAll()
    }
    private func intercept(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopTap(); recording = false; needsDisplay = true
            return false
        }
        guard let native = NSEvent(cgEvent: event) else { return false }
        if type == .keyDown { downKeys.insert(native.keyCode); keyDown(with: native) }
        if type == .keyUp { downKeys.remove(native.keyCode) }
        if type == .flagsChanged { flagsChanged(with: native) }
        if !recording, downKeys.isEmpty, event.flags.rawValue & 0x9e0000 == 0 { stopTap() }
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        if recording {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // Recording indicator dot
            let dotRect = NSRect(x: 14, y: (bounds.height - 8) / 2, width: 8, height: 8)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            let text = "请按下快捷键组合…"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: .init(x: 28, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 1.0
            path.stroke()

            let isRecorded = savedLabel != "录制快捷键" && savedLabel != "无法录制，请手动选择"
            let text = isRecorded ? savedLabel : "点击开始录制快捷键…"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isRecorded ? .semibold : .regular),
                .foregroundColor: isRecorded ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: .init(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
    }
    override func keyDown(with event: NSEvent) {
        guard recording, !event.isARepeat else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        let names: [UInt16: String] = [36: "↩", 48: "Tab", 49: "空格", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let name = names[event.keyCode] ?? event.charactersIgnoringModifiers.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "键\(event.keyCode)"
        finish(.init(code: event.keyCode, modifiers: UInt64(modifiers.rawValue), label: Self.prefix(modifiers) + name))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }; keyDown(with: event); return true
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording, let mask = ShortcutEventPlan.mask(for: event.keyCode) else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control, .function])
        if UInt64(modifiers.rawValue) & mask != 0 {
            modifierCandidate = .init(code: event.keyCode, modifiers: mask, label: Self.prefix(NSEvent.ModifierFlags(rawValue: UInt(mask))))
        } else if let candidate = modifierCandidate, candidate.code == event.keyCode {
            finish(candidate)
        }
    }
    private func finish(_ key: ShortcutKey) {
        guard key.isValid else { return }
        onCapture(key); savedLabel = key.label; recording = false; modifierCandidate = nil; needsDisplay = true
    }
    private static func prefix(_ flags: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "Fn ")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }
}
