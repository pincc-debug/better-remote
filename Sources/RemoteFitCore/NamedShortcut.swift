import Foundation

public struct ShortcutKey: Codable, Equatable, Sendable {
    public var code: UInt16
    public var modifiers: UInt64
    public var label: String
    public init(code: UInt16, modifiers: UInt64, label: String) {
        self.code = code; self.modifiers = modifiers; self.label = label
    }
    public var displayLabel: String {
        if ShortcutEventPlan.mask(for: code) != nil { return label }
        let modifiers: [(UInt64, String)] = [(1 << 23, "Fn"), (1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘")]
        let prefix = modifiers.filter { self.modifiers & $0.0 != 0 }.map { $0.1 }.joined()
        return label.hasPrefix(prefix) ? label : prefix + label
    }
    public var isValid: Bool { code < 128 && !label.isEmpty && modifiers & ~UInt64(0x9e0000) == 0 }
}
public struct NamedShortcut: Codable, Identifiable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case press, doublePress, hold, tapHold
        public var title: String {
            clickCount == 1 ? "单击" : "双击"
        }
        public var clickCount: Int {
            switch self {
            case .press, .hold: 1
            case .doublePress, .tapHold: 2
            }
        }
        public var holdsLast: Bool {
            switch self {
            case .hold, .tapHold: true
            default: false
            }
        }
        public static func resolved(clicks: Int, holdsLast: Bool) -> Mode {
            switch (clicks > 1, holdsLast) {
            case (false, false): .press
            case (false, true): .hold
            case (true, false): .doublePress
            case (true, true): .tapHold
            }
        }
    }
    public var id: String
    public var name: String
    public var key: ShortcutKey
    public var icon: ShortcutIcon
    public var mode: Mode
    public var enabled: Bool
    public init(id: String = UUID().uuidString, name: String, key: ShortcutKey, mode: Mode = .press, icon: ShortcutIcon = .keyboard, enabled: Bool = true) {
        self.id = id; self.name = name; self.key = key; self.mode = mode; self.icon = icon; self.enabled = enabled
    }
    private enum CodingKeys: String, CodingKey { case id, name, key, mode, icon, enabled }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        key = try c.decode(ShortcutKey.self, forKey: .key)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .press
        icon = ShortcutIcon(rawValue: try c.decodeIfPresent(String.self, forKey: .icon) ?? "") ?? .keyboard
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
    public var isValid: Bool { key.isValid && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 32 }
}
public struct ShortcutStroke: Equatable, Sendable {
    public var code: UInt16
    public var flags: UInt64
    public var down: Bool
    public var modifier: Bool
}
public enum ShortcutEventPlan {
    // Generic modifier masks match CGEventFlags and NSEvent.ModifierFlags.
    public static let modifierKeys: [(UInt16, UInt64)] = [(55, 1 << 20), (56, 1 << 17), (58, 1 << 19), (59, 1 << 18), (63, 1 << 23)]
    public static func mask(for code: UInt16) -> UInt64? {
        switch code {
        case 54, 55: 1 << 20
        case 56, 60: 1 << 17
        case 58, 61: 1 << 19
        case 59, 62: 1 << 18
        case 63: 1 << 23
        default: nil
        }
    }
    public static func deviceMask(for code: UInt16) -> UInt64 {
        switch code {
        case 55: 0x08
        case 54: 0x10
        case 56: 0x02
        case 60: 0x04
        case 58: 0x20
        case 61: 0x40
        case 59: 0x01
        case 62: 0x2000
        default: 0
        }
    }
    public static func strokes(for key: ShortcutKey) -> (press: [ShortcutStroke], release: [ShortcutStroke]) {
        guard key.isValid else { return ([], []) }
        if let mask = mask(for: key.code) {
            return ([.init(code: key.code, flags: mask | deviceMask(for: key.code), down: true, modifier: true)],
                    [.init(code: key.code, flags: 0, down: false, modifier: true)])
        }
        var flags: UInt64 = 0
        var press: [ShortcutStroke] = []
        let modifiers = modifierKeys.filter { key.modifiers & $0.1 != 0 }
        for (code, mask) in modifiers {
            flags |= mask | deviceMask(for: code); press.append(.init(code: code, flags: flags, down: true, modifier: true))
        }
        press.append(.init(code: key.code, flags: flags, down: true, modifier: false))
        var release: [ShortcutStroke] = [.init(code: key.code, flags: flags, down: false, modifier: false)]
        for (code, mask) in modifiers.reversed() {
            flags &= ~(mask | deviceMask(for: code)); release.append(.init(code: code, flags: flags, down: false, modifier: true))
        }
        return (press, release)
    }
}

extension NamedShortcut {
    public static let recommendedPresets: [NamedShortcut] =
        (try? ShortcutPresetCatalog.bundled().presets) ?? []
}
