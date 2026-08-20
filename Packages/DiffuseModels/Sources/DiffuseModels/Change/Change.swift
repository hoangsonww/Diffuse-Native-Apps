import Foundation

/// A single before/after pair for one property.
public struct PropertyChange: Sendable, Hashable, Codable {
    public let key: PropertyKey
    public let displayName: String
    public let unit: PropertyUnit
    public let before: PropertyValue
    public let after: PropertyValue

    public init(
        key: PropertyKey,
        displayName: String,
        unit: PropertyUnit = .none,
        before: PropertyValue,
        after: PropertyValue
    ) {
        self.key = key
        self.displayName = displayName
        self.unit = unit
        self.before = before
        self.after = after
    }

    /// Signed numeric delta where both sides are numeric, otherwise `nil`.
    public var delta: Double? {
        guard let before = before.numericValue, let after = after.numericValue else { return nil }
        return after - before
    }

    /// Whether the value moved up, down, or is not orderable.
    public var direction: Direction {
        if let before = before.versionValue, let after = after.versionValue, before != after {
            return after > before ? .increased : .decreased
        }
        guard let delta, delta != 0 else { return .lateral }
        return delta > 0 ? .increased : .decreased
    }

    public enum Direction: String, Sendable, Hashable, Codable {
        case increased, decreased, lateral

        public var symbol: String {
            switch self {
            case .increased: "arrow.up.right"
            case .decreased: "arrow.down.right"
            case .lateral: "arrow.right"
            }
        }
    }

    /// `24.5.0 → 24.6.0`
    public func formatted(style: PropertyFormatStyle = .standard) -> String {
        "\(before.formatted(style: style)) → \(after.formatted(style: style))"
    }
}

/// A deterministic identifier for a change, derived from what changed rather
/// than from a random UUID. Two runs of the diff engine over the same pair of
/// snapshots produce byte-identical results, which is what makes golden
/// fixtures viable.
public struct ChangeID: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(capability: CapabilityID, identity: EntityIdentity, property: PropertyKey?, kind: ChangeKind) {
        var parts = [capability.rawValue, identity.token, kind.rawValue]
        if let property {
            parts.insert(property.rawValue, at: 2)
        }
        rawValue = parts.joined(separator: "#")
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: ChangeID, rhs: ChangeID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One difference between two snapshots.
///
/// A change is fully self-describing: it names the capability, the entity and
/// (for modifications) the property, and carries the presentation metadata the
/// UI needs. Nothing downstream has to look anything up.
public struct Change: Sendable, Hashable, Codable, Identifiable {
    public let id: ChangeID
    public let kind: ChangeKind
    public let capability: CapabilityID
    public let sectionName: String
    public let category: SectionCategory
    public let entity: EntityReference

    /// `nil` for whole-entity additions and removals.
    public let property: PropertyChange?

    public let severity: ChangeSeverity

    /// How sure the engine is that this is a real change rather than
    /// measurement noise. Values below 1 come from tolerance-based comparisons.
    public let confidence: Double

    public let privacy: PrivacyClassification

    /// When the change was observed — the capture time of the later snapshot,
    /// refined by the section's own collection time where available. Used by
    /// temporal correlation.
    public let observedAt: Date

    /// A one-line human summary, e.g. `Node 24.5.0 → 24.6.0`.
    public let summary: String
    public let detail: String?

    public init(
        id: ChangeID,
        kind: ChangeKind,
        capability: CapabilityID,
        sectionName: String,
        category: SectionCategory,
        entity: EntityReference,
        property: PropertyChange? = nil,
        severity: ChangeSeverity,
        confidence: Double = 1.0,
        privacy: PrivacyClassification = .local,
        observedAt: Date,
        summary: String,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.capability = capability
        self.sectionName = sectionName
        self.category = category
        self.entity = entity
        self.property = property
        self.severity = severity
        self.confidence = confidence
        self.privacy = privacy
        self.observedAt = observedAt
        self.summary = summary
        self.detail = detail
    }

    /// `Network › Wi-Fi`
    public var breadcrumb: String {
        "\(sectionName) › \(entity.displayName)"
    }

    public var searchText: String {
        [
            sectionName, entity.displayName, entity.subtitle ?? "", summary, detail ?? "",
            capability.rawValue, property?.displayName ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

/// Deterministic presentation order: most severe first, then by section, entity
/// and property, so two runs always agree.
public extension [Change] {
    func sortedForPresentation() -> [Change] {
        sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.category != rhs.category {
                return lhs.category < rhs.category
            }
            if lhs.capability != rhs.capability {
                return lhs.capability < rhs.capability
            }
            if lhs.entity.identity != rhs.entity.identity {
                return lhs.entity.identity < rhs.entity.identity
            }
            return lhs.id < rhs.id
        }
    }

    func filtered(minimumSeverity: ChangeSeverity) -> [Change] {
        filter { $0.severity >= minimumSeverity }
    }
}
