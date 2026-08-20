import DiffuseModels
import Foundation

/// Something Diffuse knows how to observe.
///
/// A capability answers three questions: what it is (`metadata`), whether it
/// can run right now (`availability()`), and how to read it (`makeCollector()`).
/// Nothing else in the system needs to know a capability exists at compile
/// time; the platform registry discovers them at launch.
public protocol DiffuseCapability: Sendable {
    associatedtype Collector: SnapshotCollector

    var id: CapabilityID { get }
    var metadata: CapabilityMetadata { get }

    /// Checks whether this capability can produce data on this device right
    /// now. Must be cheap: it runs for every capability on every launch.
    func availability() async -> CapabilityAvailability

    func makeCollector() -> Collector
}

public extension DiffuseCapability {
    var id: CapabilityID {
        metadata.id
    }
}

/// A strongly typed collection result.
///
/// Collectors return their own domain structs — `GitSnapshot`, `DisplaySnapshot`
/// — which project into the generic entity representation here. That keeps
/// collector code type-safe and readable while everything downstream stays
/// capability-agnostic.
public protocol CollectedSection: Sendable {
    /// The schema describing this section's entities. Static because it must
    /// be available without having collected anything, for documentation and
    /// for placeholder sections.
    static var schema: SectionSchema { get }

    var entities: [SnapshotEntity] { get }
    var attributes: [PropertyKey: PropertyValue] { get }
    var diagnostics: [Diagnostic] { get }

    /// Lets a collector report that it only got part of what it wanted without
    /// throwing away the part it did get.
    var status: CollectionStatus { get }
}

public extension CollectedSection {
    var attributes: [PropertyKey: PropertyValue] {
        [:]
    }

    var diagnostics: [Diagnostic] {
        []
    }

    var status: CollectionStatus {
        .collected
    }
}

/// Reads the current value of one capability.
public protocol SnapshotCollector: Sendable {
    associatedtype Output: CollectedSection

    var identifier: CollectorID { get }

    /// Bumped when the collector's output changes shape. Stored on every
    /// section so an old snapshot can be interpreted correctly later.
    var version: SemanticVersion { get }

    func collect(context: CollectionContext) async throws -> Output
}

public extension SnapshotCollector {
    var version: SemanticVersion {
        "1.0.0"
    }
}

/// Everything a collector is allowed to know about the run it is part of.
///
/// Passing this in rather than letting collectors reach for `Date()` or
/// `ProcessInfo` directly is what makes collector tests deterministic.
public struct CollectionContext: Sendable {
    public let startedAt: Date
    public let platform: Platform
    public let origin: SnapshotOrigin

    /// How long this collector may take before the coordinator abandons it.
    public let deadline: Duration

    /// True when the snapshot was triggered without the app in the foreground,
    /// e.g. an iOS background refresh. Expensive work should be skipped.
    public let isBackground: Bool

    public init(
        startedAt: Date,
        platform: Platform,
        origin: SnapshotOrigin = .manual,
        deadline: Duration = .seconds(5),
        isBackground: Bool = false
    ) {
        self.startedAt = startedAt
        self.platform = platform
        self.origin = origin
        self.deadline = deadline
        self.isBackground = isBackground
    }
}

/// Failures a collector can report. Every case is recoverable at the section
/// level: the coordinator records it and moves on.
public enum CollectorError: Error, Sendable, Hashable {
    case unavailable(String)
    case permissionDenied(String)
    case timedOut
    case malformedOutput(String)
    case underlying(String)

    public var status: CollectionStatus {
        switch self {
        case .unavailable: .unavailable
        case .permissionDenied: .permissionRequired
        case .timedOut: .timedOut
        case .malformedOutput, .underlying: .failed
        }
    }

    public var message: String {
        switch self {
        case let .unavailable(reason): reason
        case let .permissionDenied(reason): reason
        case .timedOut: "The collector exceeded its deadline."
        case let .malformedOutput(reason): "Unexpected output: \(reason)"
        case let .underlying(reason): reason
        }
    }
}
