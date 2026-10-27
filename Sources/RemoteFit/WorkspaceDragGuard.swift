import AppKit
import ApplicationServices
import RemoteFitCore

/// Filters mouse drags before delivery to applications. WindowServer geometry
/// confirms custom-titlebar movement; AX hit testing identifies native chrome.
/// It is not a system work-area reservation (fullscreen and non-AX apps differ).
@MainActor
final class WorkspaceDragGuard {
    var region: () -> WorkspaceLayoutController.Region? = { nil }
    var changed: () -> Void = {}
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private struct Drag {
        let id: CGWindowID
        let start: CGPoint
        let frame: CGRect
        var last: CGPoint
        var kind: WorkspaceDragBoundary.Kind?
        var didDrag = false
    }
    private var drag: Drag?

    func start() -> Bool {
        if tap != nil { return true }
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    Unmanaged<WorkspaceDragGuard>.fromOpaque(context).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        drag = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            drag = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let region = region() else { drag = nil; return }
        if type == .leftMouseDown {
            drag = candidate(at: event.location, region: region)
        } else if type == .leftMouseDragged || type == .leftMouseUp, var drag {
            let point = event.location
            if type == .leftMouseDragged { drag.didDrag = true }
            if drag.kind == nil, type == .leftMouseDragged, let current = windowFrame(drag.id) {
                // Custom titlebars may expose generic content to AX. Confirm an
                // actual window move before constraining, preserving text/file drags.
                let delta = CGPoint(x: drag.last.x - drag.start.x, y: drag.last.y - drag.start.y)
                let moved = CGPoint(x: current.minX - drag.frame.minX, y: current.minY - drag.frame.minY)
                if abs(delta.x) + abs(delta.y) > 3,
                   abs(moved.x - delta.x) < 3, abs(moved.y - delta.y) < 3,
                   abs(moved.x) + abs(moved.y) > 3,
                   abs(current.width - drag.frame.width) < 2, abs(current.height - drag.frame.height) < 2 {
                    drag.kind = .move
                }
            }
            if let kind = drag.kind, drag.didDrag {
                let bounded = WorkspaceDragBoundary.location(point, start: drag.start, window: drag.frame, area: region.area, kind: kind)
                if bounded != point {
                    event.location = bounded
                    event.setIntegerValueField(.mouseEventDeltaX, value: Int64((bounded.x - drag.last.x).rounded()))
                    event.setIntegerValueField(.mouseEventDeltaY, value: Int64((bounded.y - drag.last.y).rounded()))
                    // Only the delivered event is clamped; never warp the real cursor
                    // (warping briefly suppresses local mouse input and reads as a jump).
                }
            }
            drag.last = event.location
            self.drag = type == .leftMouseUp ? nil : drag
            if type == .leftMouseUp, drag.didDrag { changed() }
        }
    }

    private func candidate(at point: CGPoint, region: WorkspaceLayoutController.Region) -> Drag? {
        guard region.area.contains(point) else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.insetBy(dx: -5, dy: -5).contains(point) else { continue }
            // Do not reach through an overlay/menu into a window beneath it.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  let id = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            let owner = WindowLayout.screen(containing: frame, screens: NSScreen.screens.map(WindowController.accessibilityFrame), fallback: region.screen)
            guard owner == region.screen else { return nil }
            var kind: WorkspaceDragBoundary.Kind?
            if abs(point.x - frame.maxX) <= 5 { kind = .resizeRight }
            else if abs(point.x - frame.minX) <= 5 { kind = .resizeLeft }
            else if isTitlebar(at: point, pid: pid, frame: frame) { kind = .move }
            return Drag(id: id.uint32Value, start: point, frame: frame, last: point, kind: kind)
        }
        return nil
    }

    private func isTitlebar(at point: CGPoint, pid: pid_t, frame: CGRect) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let hit else { return false }
        AXUIElementSetMessagingTimeout(hit, 0.025)
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role) == .success else { return false }
        let name = role as? String
        if name == "AXTitleBar" { return true }
        // Native empty titlebar areas hit the window itself, not its content.
        return name == kAXWindowRole && point.y >= frame.minY && point.y < frame.minY + 28
    }

    private func windowFrame(_ id: CGWindowID) -> CGRect? {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let info = list.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }
}
