import DiffuseModels
import Foundation

/// A capability assembled from closures.
///
/// Most capabilities have no state beyond their metadata, so this removes the
/// boilerplate of declaring a type per capability. A collector author writes a
/// typed `CollectedSection`, a `SnapshotCollector`, and one of these.
public struct BasicCapability<Collector: SnapshotCollector>: DiffuseCapability {
    public let metadata: CapabilityMetadata

    private let _availability: @Sendable () async -> CapabilityAvailability
    private let _makeCollector: @Sendable () -> Collector

    public init(
        metadata: CapabilityMetadata,
        availability: @escaping @Sendable () async -> CapabilityAvailability = { .available },
        collector: @escaping @Sendable () -> Collector
    ) {
        self.metadata = metadata
        _availability = availability
        _makeCollector = collector
    }

    public func availability() async -> CapabilityAvailability {
        await _availability()
    }

    public func makeCollector() -> Collector {
        _makeCollector()
    }

    /// Convenience for registering into a `StaticCapabilityRegistry`.
    public var erased: AnyCapability {
        AnyCapability(self)
    }
}

public extension CapabilityMetadata {
    /// Builds metadata from a collected section type, avoiding the need to
    /// repeat the schema in two places.
    static func describing<Section: CollectedSection>(
        _: Section.Type,
        summary: String,
        collectionDescription: String,
        platforms: Set<Platform>,
        permissions: [PermissionRequirement] = [],
        isEnabledByDefault: Bool = true,
        cost: CollectionCost = .low,
        privacy: PrivacyClassification? = nil
    ) -> CapabilityMetadata {
        let schema = Section.schema
        return CapabilityMetadata(
            id: schema.capability,
            displayName: schema.displayName,
            summary: summary,
            collectionDescription: collectionDescription,
            category: schema.category,
            symbol: schema.symbol,
            privacy: privacy ?? schema.privacy,
            platforms: platforms,
            permissions: permissions,
            schema: schema,
            isEnabledByDefault: isEnabledByDefault,
            cost: cost
        )
    }
}
