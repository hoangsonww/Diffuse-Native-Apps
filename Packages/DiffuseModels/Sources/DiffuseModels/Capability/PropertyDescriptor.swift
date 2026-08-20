import Foundation

/// The unit a numeric property is measured in. Drives both formatting and the
/// default tolerance used when comparing two readings.
public enum PropertyUnit: String, Sendable, Hashable, Codable, CaseIterable {
    case none
    case bytes
    case seconds
    case percent
    case count
    case hertz
    case celsius
    case pixels
    case path
    case version
    case timestamp

    public var suffix: String? {
        switch self {
        case .hertz: "Hz"
        case .celsius: "°C"
        case .pixels: "px"
        default: nil
        }
    }
}

/// How two readings of the same property should be compared.
///
/// This is the single extension point that keeps the diff engine free of
/// `if capability == .docker` branches. A capability declares the rule; the
/// engine applies it.
public enum ComparisonRule: Sendable, Hashable, Codable {
    /// Byte-for-byte equality.
    case exact

    /// Equality ignoring case and surrounding whitespace.
    case caseInsensitive

    /// Equality after home-directory and trailing-separator normalization.
    case pathNormalized

    /// Semantic version precedence; `1.2.0` and `1.2` are equal.
    case semanticVersion

    /// Numeric equality within an absolute tolerance, in the property's unit.
    case numeric(tolerance: Double)

    /// Numeric equality within a fractional tolerance of the larger value.
    /// Suited to values that drift constantly, like free disk space.
    case relative(tolerance: Double)

    /// List equality ignoring element order.
    case unordered

    /// The property is recorded but never produces a change. Useful for
    /// timestamps and counters that are pure noise.
    case ignored

    /// A sensible default for the given unit.
    public static func `default`(for unit: PropertyUnit) -> ComparisonRule {
        switch unit {
        case .bytes: .relative(tolerance: 0.01)
        case .percent: .numeric(tolerance: 0.05)
        case .seconds: .relative(tolerance: 0.1)
        case .celsius: .numeric(tolerance: 2)
        case .path: .pathNormalized
        case .version: .semanticVersion
        case .timestamp: .ignored
        default: .exact
        }
    }
}

/// Describes one property of one entity kind: what it is called, what it means,
/// how to compare it and how much a change to it matters.
///
/// Descriptors travel *inside* the snapshot. A snapshot exported from a machine
/// running a newer build, with capabilities this build has never heard of, can
/// still be diffed and rendered correctly.
public struct PropertyDescriptor: Sendable, Hashable, Codable, Identifiable {
    public let key: PropertyKey
    public var displayName: String
    public var summary: String?
    public var unit: PropertyUnit
    public var comparison: ComparisonRule

    /// Severity applied when this property changes, before escalation rules.
    public var severity: ChangeSeverity
    public var privacy: PrivacyClassification

    /// Shown in collapsed entity rows and in compact platform UIs.
    public var isPrimary: Bool

    /// Position within the entity's detail view. Lower sorts first.
    public var displayOrder: Int

    public var id: PropertyKey {
        key
    }

    public init(
        key: PropertyKey,
        displayName: String,
        summary: String? = nil,
        unit: PropertyUnit = .none,
        comparison: ComparisonRule? = nil,
        severity: ChangeSeverity = .notable,
        privacy: PrivacyClassification = .public,
        isPrimary: Bool = false,
        displayOrder: Int = 0
    ) {
        self.key = key
        self.displayName = displayName
        self.summary = summary
        self.unit = unit
        self.comparison = comparison ?? .default(for: unit)
        self.severity = severity
        self.privacy = privacy
        self.isPrimary = isPrimary
        self.displayOrder = displayOrder
    }
}

/// Describes a kind of entity a capability can produce.
public struct EntityKindDescriptor: Sendable, Hashable, Codable, Identifiable {
    public let kind: EntityKind
    public var singularName: String
    public var pluralName: String
    public var symbol: String
    public var summary: String?

    /// Severity used when an entity of this kind appears.
    public var additionSeverity: ChangeSeverity

    /// Severity used when an entity of this kind disappears. Usually higher
    /// than addition: a display vanishing matters more than one appearing.
    public var removalSeverity: ChangeSeverity

    public var properties: [PropertyDescriptor]

    public var id: EntityKind {
        kind
    }

    public init(
        kind: EntityKind,
        singularName: String,
        pluralName: String? = nil,
        symbol: String = "circle.grid.2x2",
        summary: String? = nil,
        additionSeverity: ChangeSeverity = .notable,
        removalSeverity: ChangeSeverity = .significant,
        properties: [PropertyDescriptor] = []
    ) {
        self.kind = kind
        self.singularName = singularName
        self.pluralName = pluralName ?? singularName + "s"
        self.symbol = symbol
        self.summary = summary
        self.additionSeverity = additionSeverity
        self.removalSeverity = removalSeverity
        self.properties = properties
    }

    public func descriptor(for key: PropertyKey) -> PropertyDescriptor? {
        properties.first { $0.key == key }
    }

    /// Properties in presentation order.
    public var orderedProperties: [PropertyDescriptor] {
        properties.sorted { ($0.displayOrder, $0.key) < ($1.displayOrder, $1.key) }
    }

    public var primaryProperties: [PropertyDescriptor] {
        orderedProperties.filter(\.isPrimary)
    }
}

/// The self-describing schema attached to every collected section.
public struct SectionSchema: Sendable, Hashable, Codable, Identifiable {
    public let capability: CapabilityID
    public var displayName: String
    public var summary: String
    public var category: SectionCategory
    public var symbol: String
    public var privacy: PrivacyClassification
    public var entityKinds: [EntityKindDescriptor]

    /// Section-level scalars that are not attached to any entity, e.g. total
    /// free space for the storage section.
    public var attributes: [PropertyDescriptor]

    public var displayOrder: Int

    public var id: CapabilityID {
        capability
    }

    public init(
        capability: CapabilityID,
        displayName: String,
        summary: String,
        category: SectionCategory,
        symbol: String? = nil,
        privacy: PrivacyClassification = .local,
        entityKinds: [EntityKindDescriptor] = [],
        attributes: [PropertyDescriptor] = [],
        displayOrder: Int = 0
    ) {
        self.capability = capability
        self.displayName = displayName
        self.summary = summary
        self.category = category
        self.symbol = symbol ?? category.symbol
        self.privacy = privacy
        self.entityKinds = entityKinds
        self.attributes = attributes
        self.displayOrder = displayOrder
    }

    public func descriptor(for kind: EntityKind) -> EntityKindDescriptor? {
        entityKinds.first { $0.kind == kind }
    }

    public func attributeDescriptor(for key: PropertyKey) -> PropertyDescriptor? {
        attributes.first { $0.key == key }
    }

    /// Looks up a property descriptor for an entity kind, falling back to a
    /// permissive default so that unknown properties still diff sensibly
    /// instead of being silently dropped.
    public func descriptor(for key: PropertyKey, in kind: EntityKind) -> PropertyDescriptor {
        descriptor(for: kind)?.descriptor(for: key)
            ?? PropertyDescriptor(
                key: key,
                displayName: key.rawValue.humanizedIdentifier,
                severity: .notable,
                privacy: .local
            )
    }
}

public extension String {
    /// Turns `refreshRate` or `refresh_rate` into `Refresh Rate` for schemas
    /// that omit a display name.
    var humanizedIdentifier: String {
        let spaced = replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        var output = ""
        for (index, character) in spaced.enumerated() {
            if character.isUppercase, index > 0, output.last?.isWhitespace == false, output.last?.isUppercase == false {
                output.append(" ")
            }
            output.append(character)
        }
        return output.prefix(1).uppercased() + output.dropFirst()
    }
}
