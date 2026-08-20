import Foundation

/// Everything the UI needs to present a capability without knowing what it is.
///
/// Lives in `DiffuseModels` rather than `DiffuseCapabilities` so that metadata
/// can be embedded in exported snapshots and rendered by a build that does not
/// have the capability implementation compiled in.
public struct CapabilityMetadata: Sendable, Hashable, Codable, Identifiable {
    public let id: CapabilityID
    public var displayName: String
    public var summary: String

    /// One sentence, shown verbatim in the privacy sheet, describing exactly
    /// what this capability reads.
    public var collectionDescription: String

    public var category: SectionCategory
    public var symbol: String
    public var privacy: PrivacyClassification
    public var platforms: Set<Platform>
    public var permissions: [PermissionRequirement]

    /// The schema this capability's collector emits.
    public var schema: SectionSchema

    /// Whether the capability is enabled by default on a fresh install.
    public var isEnabledByDefault: Bool

    /// Capabilities whose data is more expensive to gather can be excluded from
    /// frequent automatic snapshots.
    public var cost: CollectionCost

    public init(
        id: CapabilityID,
        displayName: String,
        summary: String,
        collectionDescription: String,
        category: SectionCategory,
        symbol: String? = nil,
        privacy: PrivacyClassification = .local,
        platforms: Set<Platform>,
        permissions: [PermissionRequirement] = [],
        schema: SectionSchema,
        isEnabledByDefault: Bool = true,
        cost: CollectionCost = .low
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.collectionDescription = collectionDescription
        self.category = category
        self.symbol = symbol ?? schema.symbol
        self.privacy = privacy
        self.platforms = platforms
        self.permissions = permissions
        self.schema = schema
        self.isEnabledByDefault = isEnabledByDefault
        self.cost = cost
    }
}

/// A rough indication of how expensive collection is, used by the scheduler.
public enum CollectionCost: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    /// In-memory or single syscall. Always collected.
    case low

    /// Filesystem traversal or a handful of subprocesses.
    case moderate

    /// Multiple subprocesses that can each take seconds, e.g. Docker.
    case high

    public static func < (lhs: CollectionCost, rhs: CollectionCost) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    /// Default per-collector timeout. A slow collector must never be able to
    /// hold up the rest of a snapshot.
    public var defaultTimeout: Duration {
        switch self {
        case .low: .seconds(2)
        case .moderate: .seconds(5)
        case .high: .seconds(12)
        }
    }

    public var displayName: String {
        switch self {
        case .low: "Fast"
        case .moderate: "Moderate"
        case .high: "Slow"
        }
    }
}

/// A permission a capability needs before it can collect anything.
public struct PermissionRequirement: Sendable, Hashable, Codable, Identifiable {
    /// A stable identifier such as `location.whenInUse` or `fullDiskAccess`.
    public let id: String
    public var displayName: String

    /// User-facing justification. Shown before the system prompt appears.
    public var rationale: String

    /// Whether the capability can still produce a partial section without it.
    public var isRequired: Bool

    /// A deep link the UI can offer, e.g. a System Settings URL.
    public var settingsURL: URL?

    public init(
        id: String,
        displayName: String,
        rationale: String,
        isRequired: Bool = true,
        settingsURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.rationale = rationale
        self.isRequired = isRequired
        self.settingsURL = settingsURL
    }
}
