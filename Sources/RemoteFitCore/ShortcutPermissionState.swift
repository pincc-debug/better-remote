import Foundation

public struct ShortcutPermissionState: Equatable, Sendable {
    public var accessibility: Bool
    public var eventPosting: Bool
    public init(accessibility: Bool, eventPosting: Bool) {
        self.accessibility = accessibility; self.eventPosting = eventPosting
    }
    // AX is the authority for the Accessibility status shown to the user.
    // Event-posting readiness is separately requested when sending a shortcut.
    public var granted: Bool { accessibility }
    public var title: String {
        if granted { return "已授权" }
        return "未授权"
    }
}
