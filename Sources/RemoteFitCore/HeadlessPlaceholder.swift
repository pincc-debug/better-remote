import Foundation

/// With the lid closed and every monitor off, macOS can publish a generic "Display"
/// (vendor 'unkn', model 'virt', serial 0, not built-in) so WindowServer keeps a desktop.
/// It cannot be mirrored (CGConfigureDisplayMirrorOfDisplay fails with 1001) and macOS
/// removes or re-creates it on its own, so a session never mirrors, verifies or restores it.
public enum HeadlessPlaceholder {
    public static let vendor: UInt32 = 0x756E_6B6E // 'unkn'
    public static let model: UInt32 = 0x7669_7274  // 'virt'

    public static func isPlaceholder(hardwareKey: String) -> Bool {
        hardwareKey == "\(vendor):\(model):0:false"
    }
    public static func isPlaceholder(_ state: DisplayState) -> Bool { isPlaceholder(hardwareKey: state.hardwareKey) }

    /// Displays that may join the session's mirror set.
    public static func mirrorable(_ states: [DisplayState]) -> [DisplayState] { states.filter { !isPlaceholder($0) } }

    /// Live displays as verification should see them: placeholders come and go freely.
    public static func ignoringPlaceholders(_ live: [DisplayState]) -> [DisplayState] { mirrorable(live) }
}
