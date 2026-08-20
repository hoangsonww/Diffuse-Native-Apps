import Foundation

/// The outcome of running one collector.
public enum CollectionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Everything the collector set out to gather was gathered.
    case collected

    /// Some entities or properties are missing, but the section is usable.
    case partial

    /// The capability is not present on this machine right now.
    case unavailable

    /// The platform cannot support this capability at all.
    case unsupported

    /// A permission the user can grant is missing.
    case permissionRequired

    /// The collector exceeded its deadline and was abandoned.
    case timedOut

    /// The collector threw.
    case failed

    /// The user turned this capability off.
    case skipped

    /// Whether the section carries data worth diffing.
    public var hasData: Bool {
        self == .collected || self == .partial
    }

    /// Whether this status represents something the user might want to fix.
    public var isProblem: Bool {
        switch self {
        case .collected, .skipped, .unsupported: false
        case .partial, .unavailable, .permissionRequired, .timedOut, .failed: true
        }
    }

    public var displayName: String {
        switch self {
        case .collected: "Collected"
        case .partial: "Partial"
        case .unavailable: "Unavailable"
        case .unsupported: "Not supported"
        case .permissionRequired: "Permission required"
        case .timedOut: "Timed out"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    public var symbol: String {
        switch self {
        case .collected: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle"
        case .unavailable: "circle.dashed"
        case .unsupported: "minus.circle"
        case .permissionRequired: "lock.circle.fill"
        case .timedOut: "clock.badge.xmark"
        case .failed: "xmark.circle.fill"
        case .skipped: "moon.zzz"
        }
    }
}

/// A note recorded during collection. Diagnostics are how a collector explains
/// a `partial` result without failing the whole snapshot.
public struct Diagnostic: Sendable, Hashable, Codable, Identifiable {
    public enum Level: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
        case info, warning, error

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rank < rhs.rank
        }

        public var rank: Int {
            switch self {
            case .info: 0
            case .warning: 1
            case .error: 2
            }
        }

        public var symbol: String {
            switch self {
            case .info: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }
    }

    public let level: Level
    public let message: String
    public var detail: String?

    /// Derived from the content rather than generated.
    ///
    /// A random identifier here would make every snapshot containing a
    /// diagnostic differ from an otherwise identical one, which would break
    /// golden fixtures and make `diff(A, A)` non-empty.
    public var id: String {
        "\(level.rawValue):\(message):\(detail ?? "")"
    }

    public init(level: Level, message: String, detail: String? = nil) {
        self.level = level
        self.message = message
        self.detail = detail
    }

    public static func info(_ message: String, detail: String? = nil) -> Diagnostic {
        Diagnostic(level: .info, message: message, detail: detail)
    }

    public static func warning(_ message: String, detail: String? = nil) -> Diagnostic {
        Diagnostic(level: .warning, message: message, detail: detail)
    }

    public static func error(_ message: String, detail: String? = nil) -> Diagnostic {
        Diagnostic(level: .error, message: message, detail: detail)
    }
}

/// One capability's contribution to a snapshot.
///
/// A section is self-describing: it carries the schema that explains its own
/// entities, which is what lets an older build render a newer snapshot and
/// lets the diff engine work without a capability registry.
public struct SnapshotSection: Sendable, Hashable, Codable, Identifiable {
    public let capability: CapabilityID
    public let collector: CollectorID
    public let collectorVersion: SemanticVersion
    public let collectedAt: Date

    /// Wall-clock time the collector took, in seconds.
    public let duration: TimeInterval

    public var status: CollectionStatus
    public var schema: SectionSchema
    public var entities: [SnapshotEntity]

    /// Scalars that belong to the section rather than to any single entity.
    public var attributes: [PropertyKey: PropertyValue]

    public var diagnostics: [Diagnostic]

    public var id: CapabilityID {
        capability
    }

    public init(
        capability: CapabilityID,
        collector: CollectorID,
        collectorVersion: SemanticVersion,
        collectedAt: Date,
        duration: TimeInterval = 0,
        status: CollectionStatus = .collected,
        schema: SectionSchema,
        entities: [SnapshotEntity] = [],
        attributes: [PropertyKey: PropertyValue] = [:],
        diagnostics: [Diagnostic] = []
    ) {
        self.capability = capability
        self.collector = collector
        self.collectorVersion = collectorVersion
        self.collectedAt = collectedAt.roundedForSnapshot()
        self.duration = duration
        self.status = status
        self.schema = schema
        self.entities = entities
        self.attributes = attributes
        self.diagnostics = diagnostics
    }

    public var displayName: String {
        schema.displayName
    }

    public var category: SectionCategory {
        schema.category
    }

    public var symbol: String {
        schema.symbol
    }

    /// Entities in a stable order, so serialized snapshots and fixtures are
    /// byte-comparable across runs.
    public var sortedEntities: [SnapshotEntity] {
        entities.sorted { $0.identity < $1.identity }
    }

    /// Every entity including nested children.
    public var allEntities: [SnapshotEntity] {
        entities.flatMap(\.flattened)
    }

    public var entityCount: Int {
        allEntities.count
    }

    public func entities(ofKind kind: EntityKind) -> [SnapshotEntity] {
        allEntities.filter { $0.kind == kind }
    }

    public func entity(with identity: EntityIdentity) -> SnapshotEntity? {
        allEntities.first { $0.identity == identity }
    }

    /// Builds an empty section that records *why* nothing was collected. A
    /// failed collector still contributes a section so the timeline can show
    /// the gap rather than silently omitting it.
    public static func placeholder(
        capability: CapabilityID,
        collector: CollectorID,
        collectorVersion: SemanticVersion = "1.0.0",
        schema: SectionSchema,
        status: CollectionStatus,
        at date: Date,
        diagnostics: [Diagnostic] = []
    ) -> SnapshotSection {
        SnapshotSection(
            capability: capability,
            collector: collector,
            collectorVersion: collectorVersion,
            collectedAt: date,
            duration: 0,
            status: status,
            schema: schema,
            entities: [],
            attributes: [:],
            diagnostics: diagnostics
        )
    }
}
