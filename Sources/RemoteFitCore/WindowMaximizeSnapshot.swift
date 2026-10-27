import Foundation

public struct WindowMaximizeSnapshot {
    public let original: CGRect
    public let maximized: CGRect
    public init(original: CGRect, maximized: CGRect) {
        self.original = original
        self.maximized = maximized
    }
    public func restoration(from current: CGRect) -> CGRect? {
        guard !WindowLayout.approximatelyEqual(original, maximized),
              WindowLayout.approximatelyEqual(current, maximized) else { return nil }
        return original
    }
}
