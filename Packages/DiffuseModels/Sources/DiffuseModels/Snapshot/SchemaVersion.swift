import Foundation

/// The version of the serialized snapshot format.
///
/// Users keep snapshots for months or years, so every persisted snapshot
/// records the schema it was written with and the storage layer migrates
/// forward on read. The value is a plain integer because the format is
/// linear: there is exactly one migration path, oldest to newest.
public struct SchemaVersion: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        String(rawValue)
    }

    public static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The first shipped format.
    public static let v1 = SchemaVersion(1)

    /// The format written by this build.
    public static let current = SchemaVersion.v1

    /// The oldest format this build can migrate forward from.
    public static let minimumSupported = SchemaVersion.v1
}

extension SchemaVersion: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(rawValue: value)
    }
}
