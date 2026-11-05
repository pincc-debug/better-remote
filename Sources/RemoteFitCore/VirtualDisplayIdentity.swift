import Foundation

/// Two product-owned identities, stable even if preferences are reset. Adjacent
/// live displays must differ; retired identities can be reused instead of leaving
/// a new ColorSync factory profile on every connection and size change.
public enum VirtualDisplayIdentity {
    public static let vendor: UInt32 = 0x5246
    public static let product: UInt32 = 1
    public static let serials: [UInt32] = [0x4252_0001, 0x4252_0002]

    public static func next(after last: UInt32?, occupied: Set<UInt32>) -> UInt32? {
        let preferred = last == serials[0] ? [serials[1], serials[0]] : serials
        return preferred.first { !occupied.contains($0) }
    }
}

/// Only the rotation cursor is persisted. Missing state never allocates new IDs.
public struct VirtualDisplayIdentityCursor: Codable, Equatable, Sendable {
    public var lastSerial: UInt32?
    public init(lastSerial: UInt32? = nil) { self.lastSerial = lastSerial }
}
