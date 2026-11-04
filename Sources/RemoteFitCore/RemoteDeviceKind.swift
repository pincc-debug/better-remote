import Foundation

/// Best-effort guess of what kind of controller a UU device label names.
/// Only used to pick the one-finger-scroll default for a newly discovered
/// device: a computer drives the Mac with a real mouse, so press+move is a drag.
public enum RemoteDeviceKind: Equatable, Sendable {
    case computer
    case mobile
    case unknown

    /// Phone/tablet form factors. Checked before computer words so "vivo X Fold6"
    /// or "MatePad" never counts as a computer.
    static let mobileFormKeywords = ["iphone", "ipad", "phone", "pad", "fold", "flip", "tablet", "android", "手机", "平板", "安卓"]
    /// Computer words matched as plain substrings (case-insensitive).
    static let computerKeywords = ["macbook", "imac", "macmini", "mac mini", "mac studio", "mac pro", "windows",
                                   "desktop", "laptop", "notebook", "computer", "matebook", "magicbook", "redmibook",
                                   "chromebook", "thinkbook", "thinkpad", "surface", "电脑", "笔记本", "台式机", "工作站"]
    /// Short computer words that must stand alone among ASCII letters
    /// ("张三的Mac", "Windows-PC") so "Machine" or "XPCOM" do not match.
    static let computerWords = ["mac", "pc"]
    /// Phone brands: mean "phone" only when no computer word is present
    /// ("HUAWEI MateBook" stays a computer).
    static let mobileBrandKeywords = ["vivo", "iqoo", "oppo", "realme", "oneplus", "一加", "huawei", "华为", "honor", "荣耀",
                                      "xiaomi", "小米", "redmi", "红米", "samsung", "三星", "galaxy", "meizu", "魅族", "pixel", "nova"]

    public static func classify(_ name: String) -> RemoteDeviceKind {
        let text = name.lowercased()
        // ThinkPad is a laptop even though it ends in "pad".
        if text.contains("thinkpad") { return .computer }
        if mobileFormKeywords.contains(where: text.contains) { return .mobile }
        if computerKeywords.contains(where: text.contains) { return .computer }
        if computerWords.contains(where: { containsWord($0, in: text) }) { return .computer }
        if mobileBrandKeywords.contains(where: text.contains) { return .mobile }
        return .unknown
    }

    /// Substring whose neighbours are not ASCII letters (CJK, digits, punctuation are boundaries).
    static func containsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !isASCIILetter(before), !isASCIILetter(after) { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    private static func isASCIILetter(_ character: Character?) -> Bool {
        guard let character, character.isASCII else { return false }
        return character.isLetter
    }
}

extension DeviceConfiguration {
    /// Snapshot for a device seen for the first time. Computers default to
    /// one-finger scroll off; phones, tablets and unknown names copy the defaults.
    public static func newDevice(named name: String, preferences: Preferences) -> DeviceConfiguration {
        var configuration = DeviceConfiguration(preferences: preferences)
        if RemoteDeviceKind.classify(name) == .computer { configuration.uuTouchScrollEnabled = false }
        return configuration
    }
}
