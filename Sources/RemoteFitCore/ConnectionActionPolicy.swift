/// Queue expansion until all connection-time display work has finished.
public struct ConnectionToolbarPolicy: Sendable {
    private var connected = false
    private var enabled = false
    private var pending = false
    public init() {}
    public mutating func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        pending = value && connected
    }
    public mutating func connectionChanged(_ value: Bool) {
        guard connected != value else { return }
        connected = value
        pending = value && enabled
    }
    public mutating func takeAction(busy: Bool) -> Bool {
        guard connected, enabled, pending, !busy else { return false }
        pending = false
        return true
    }
}

/// Optional once-per-connection action; never executes on disconnect.
public struct ConnectionDockPolicy: Sendable {
    private var connected = false
    private var enabled = false
    private var pending = false
    private var handled = false
    public init() {}
    public mutating func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        pending = value && connected && !handled
    }
    public mutating func connectionChanged(_ value: Bool) {
        guard value != connected else { return }
        connected = value
        handled = false
        pending = value && enabled
    }
    public mutating func takeAction(busy: Bool) -> Bool {
        guard pending, !busy else { return false }
        pending = false; handled = true
        return true
    }
}
