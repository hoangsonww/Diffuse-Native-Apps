import Foundation

/// A namespaced identifier for something Diffuse knows how to observe, such as
/// `system.info`, `network.wifi` or `development.git`.
///
/// Capability identifiers are deliberately *values*, not cases of a
/// product-wide enum. Adding a capability must never require editing a central
/// list that the diff engine, storage layer or UI switch over.
public struct CapabilityID: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// The leading segment of the identifier, e.g. `development` for `development.git`.
    public var namespace: String {
        rawValue.split(separator: ".").first.map(String.init) ?? rawValue
    }

    /// The trailing segment of the identifier, e.g. `git` for `development.git`.
    public var name: String {
        rawValue.split(separator: ".").last.map(String.init) ?? rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: CapabilityID, rhs: CapabilityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension CapabilityID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// Identifies the concrete implementation that produced a section.
///
/// A capability answers *what* is observed; a collector answers *how* it was
/// observed on a specific platform. Keeping them separate lets two platforms
/// contribute to the same capability with different collectors.
public struct CollectorID: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: CollectorID, rhs: CollectorID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension CollectorID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// The type of thing an entity represents within a section, e.g. `display`,
/// `networkInterface`, `gitRepository`.
public struct EntityKind: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: EntityKind, rhs: EntityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension EntityKind: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// The key of a single observed property on an entity.
public struct PropertyKey: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: PropertyKey, rhs: PropertyKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension PropertyKey: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// Encoding dictionaries keyed by these wrappers as JSON *objects* rather than
/// flattened key/value arrays keeps the on-disk snapshot format readable and
/// diffable by hand.
extension PropertyKey: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

extension CapabilityID: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

extension EntityKind: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

struct StringCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? {
        nil
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

/// A coarse grouping used purely for presentation and ordering.
///
/// Modelled as a value type rather than an enum so a new collector can
/// introduce a category without a cross-cutting change.
public struct SectionCategory: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: SectionCategory, rhs: SectionCategory) -> Bool {
        (lhs.sortIndex, lhs.rawValue) < (rhs.sortIndex, rhs.rawValue)
    }

    public static let system = SectionCategory("system")
    public static let hardware = SectionCategory("hardware")
    public static let display = SectionCategory("display")
    public static let power = SectionCategory("power")
    public static let network = SectionCategory("network")
    public static let storage = SectionCategory("storage")
    public static let software = SectionCategory("software")
    public static let development = SectionCategory("development")
    public static let security = SectionCategory("security")
    public static let accessories = SectionCategory("accessories")
    public static let other = SectionCategory("other")

    public static let wellKnown: [SectionCategory] = [
        .system, .hardware, .display, .power, .network,
        .storage, .software, .development, .security, .accessories, .other,
    ]

    /// Presentation order for well-known categories; unknown categories sort last.
    public var sortIndex: Int {
        Self.wellKnown.firstIndex(of: self) ?? Self.wellKnown.count
    }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .hardware: "Hardware"
        case .display: "Displays"
        case .power: "Power"
        case .network: "Network"
        case .storage: "Storage"
        case .software: "Software"
        case .development: "Development"
        case .security: "Security"
        case .accessories: "Accessories"
        case .other: "Other"
        default: rawValue.capitalized
        }
    }

    public var symbol: String {
        switch self {
        case .system: "cpu"
        case .hardware: "desktopcomputer"
        case .display: "display"
        case .power: "battery.100"
        case .network: "network"
        case .storage: "internaldrive"
        case .software: "shippingbox"
        case .development: "hammer"
        case .security: "lock.shield"
        case .accessories: "cable.connector"
        default: "square.grid.2x2"
        }
    }
}

extension SectionCategory: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
