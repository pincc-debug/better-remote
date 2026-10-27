import Foundation

/// An editable copy of a preset. Neither stepping nor scaling mutates the preset.
public struct ResolutionAdjustment: Equatable, Sendable {
    public enum Control: Sendable { case width, height, scale }
    public static let pixelStep = 32
    public static let scaleStep = 10
    public var base: Dimensions
    public private(set) var scalePercent: Int = 100
    public init(_ dimensions: Dimensions) { base = dimensions }
    public var dimensions: Dimensions {
        .init(Int((Double(base.width) * 100 / Double(scalePercent)).rounded()),
              Int((Double(base.height) * 100 / Double(scalePercent)).rounded()))
    }
    public func settingScale(_ percent: Int) -> Self? {
        guard (50...200).contains(percent) else { return nil }
        var next = self
        next.scalePercent = percent
        guard CustomPreset.isSupported(next.base), CustomPreset.isSupported(next.dimensions) else { return nil }
        return next
    }
    public func stepping(_ control: Control, direction: Int) -> Self? {
        guard direction == -1 || direction == 1 else { return nil }
        var next = self
        switch control {
        case .width: next.base.width += direction * Self.pixelStep
        case .height: next.base.height += direction * Self.pixelStep
        case .scale: next.scalePercent += direction * Self.scaleStep
        }
        guard (50...200).contains(next.scalePercent), CustomPreset.isSupported(next.base),
              CustomPreset.isSupported(next.dimensions) else { return nil }
        return next
    }
    public func copyPreset() -> CustomPreset {
        CustomPreset(name: dimensions.label, width: dimensions.width, height: dimensions.height)
    }
}
