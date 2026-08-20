import DiffuseModels
import Foundation

/// A type-erased capability, ready to be stored in a heterogeneous registry.
///
/// Erasure happens once, at registration, and folds the collector's typed
/// output into a generic `SnapshotSection`. Everything above this line —
/// coordinator, storage, diff, UI, CLI — deals only in `SnapshotSection`.
public struct AnyCapability: Sendable, Identifiable {
    public let id: CapabilityID
    public let metadata: CapabilityMetadata

    private let _availability: @Sendable () async -> CapabilityAvailability
    private let _collect: @Sendable (CollectionContext) async throws -> SnapshotSection

    public init<Capability: DiffuseCapability>(_ capability: Capability) {
        let metadata = capability.metadata
        id = metadata.id
        self.metadata = metadata

        _availability = { await capability.availability() }

        _collect = { context in
            let collector = capability.makeCollector()
            let started = ContinuousClock.now
            let output = try await collector.collect(context: context)
            let elapsed = ContinuousClock.now - started

            return SnapshotSection(
                capability: metadata.id,
                collector: collector.identifier,
                collectorVersion: collector.version,
                collectedAt: context.startedAt,
                duration: elapsed.seconds,
                status: output.status,
                schema: Capability.Collector.Output.schema,
                entities: output.entities,
                attributes: output.attributes,
                diagnostics: output.diagnostics
            )
        }
    }

    public func availability() async -> CapabilityAvailability {
        await _availability()
    }

    /// Runs the collector. Errors propagate so the coordinator can decide how
    /// to record them; a capability never decides on its own that a snapshot
    /// should fail.
    public func collect(context: CollectionContext) async throws -> SnapshotSection {
        try await _collect(context)
    }

    /// An empty section explaining why nothing was collected. Used when the
    /// capability is unavailable, denied, timed out or switched off.
    public func placeholder(status: CollectionStatus, at date: Date,
                            diagnostics: [Diagnostic] = []) -> SnapshotSection {
        SnapshotSection.placeholder(
            capability: id,
            collector: CollectorID("\(id.rawValue).unavailable"),
            schema: metadata.schema,
            status: status,
            at: date,
            diagnostics: diagnostics
        )
    }
}

extension Duration {
    /// Seconds as a `Double`, for recording collector timings.
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
