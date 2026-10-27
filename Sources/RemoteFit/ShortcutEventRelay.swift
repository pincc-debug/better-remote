import AppKit

/// Posts our own keys after session filters, but before system hotkey dispatch.
/// The tap handles only private null wakeups; it never reads or filters typing.
@MainActor
final class ShortcutEventRelay {
    private struct Packet {
        let id: Int64
        let events: [CGEvent]
    }
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var packets: [Packet] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finishRequested = false
    var isPrepared: Bool { tap != nil }
    private var nextID = Int64.random(in: 1...(Int64.max / 2))
    private let ownPID = Int64(ProcessInfo.processInfo.processIdentifier)

    /// Refresh placement between gestures so newly connected input tools stay
    /// before us. Never replace a tap while it still owns queued releases.
    func prepare() {
        finishRequested = false
        guard packets.isEmpty else { return }
        invalidateTap()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .defaultTap, eventsOfInterest: 1 << CGEventType.null.rawValue,
            callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    Unmanaged<ShortcutEventRelay>.fromOpaque(context).takeUnretainedValue()
                        .receive(proxy, type, event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            OperationDiagnostics.write("shortcut-relay-unavailable")
            return
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Keep the release packet alive, then remove this gesture's event tap.
    func finishWhenIdle() {
        finishRequested = true
        if packets.isEmpty { invalidateTap() }
    }

    func post(_ events: [CGEvent]) {
        guard !events.isEmpty else { return }
        guard let tap, CFMachPortIsValid(tap) else {
            events.forEach { $0.post(tap: .cghidEventTap) }
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        nextID += 1
        let id = nextID
        let wakeSource = CGEventSource(stateID: .privateState)
        wakeSource?.localEventsSuppressionInterval = 0
        guard let wakeup = CGEvent(source: wakeSource) else {
            drainAll(proxy: nil)
            events.forEach { $0.post(tap: .cghidEventTap) }
            return
        }
        packets.append(Packet(id: id, events: events))
        wakeup.setIntegerValueField(.eventSourceUserData, value: id)
        wakeup.post(tap: .cgSessionEventTap)
        // Fallback only for a wakeup that never arrived. Removing its packet
        // first makes late wakeups harmless and prevents duplicate shortcuts.
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard packets.contains(where: { $0.id == id }) else { return }
            OperationDiagnostics.write("shortcut-relay-timeout")
            drain(through: id, proxy: nil)
        }
    }

    func waitUntilDelivered() async {
        guard !packets.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func receive(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .null, event.getIntegerValueField(.eventSourceUnixProcessID) == ownPID else { return false }
        let id = event.getIntegerValueField(.eventSourceUserData)
        guard packets.contains(where: { $0.id == id }) else { return false }
        drain(through: id, proxy: proxy)
        return true
    }

    private func drain(through id: Int64, proxy: CGEventTapProxy?) {
        guard let end = packets.firstIndex(where: { $0.id == id }) else { return }
        let ready = Array(packets[...end])
        packets.removeFirst(end + 1)
        for packet in ready {
            for event in packet.events {
                if let proxy { event.tapPostEvent(proxy) }
                else { event.post(tap: .cghidEventTap) }
            }
        }
        OperationDiagnostics.write("shortcut-relay-delivered batches=\(ready.count) fallback=\(proxy == nil)")
        if packets.isEmpty {
            let completed = waiters
            waiters.removeAll()
            completed.forEach { $0.resume() }
            if finishRequested {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.finishRequested, self.packets.isEmpty else { return }
                    self.invalidateTap()
                }
            }
        }
    }

    private func drainAll(proxy: CGEventTapProxy?) {
        if let id = packets.last?.id { drain(through: id, proxy: proxy) }
    }

    private func invalidateTap() {
        if let tap { CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    isolated deinit {
        if let tap { CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    }
}
