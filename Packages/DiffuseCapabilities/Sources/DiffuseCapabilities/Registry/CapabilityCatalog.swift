import DiffuseModels
import Foundation

/// Resolves and caches the current availability of every registered capability.
///
/// Availability is checked concurrently because a slow probe (asking Docker
/// whether its daemon is up) must not delay the rest of the list. Results are
/// cached so the Capabilities screen is instant, with an explicit refresh.
public actor CapabilityCatalog {
    private let registry: any CapabilityRegistry
    private let enablementStore: (any CapabilityEnablementStoring)?
    private var cached: [CapabilityID: CapabilityAvailability] = [:]
    private var enabled: Set<CapabilityID>
    private var lastRefresh: Date?

    public init(
        registry: any CapabilityRegistry,
        enabledCapabilities: Set<CapabilityID>? = nil,
        enablementStore: (any CapabilityEnablementStoring)? = nil
    ) {
        self.registry = registry
        self.enablementStore = enablementStore
        if let enabledCapabilities {
            enabled = enabledCapabilities
        } else {
            enabled = Self.resolvedEnablement(registry: registry, stored: enablementStore?.load())
        }
    }

    public var platform: Platform {
        registry.platform
    }

    public nonisolated var capabilities: [AnyCapability] {
        registry.capabilities
    }

    public func capability(with id: CapabilityID) -> AnyCapability? {
        registry.capability(with: id)
    }

    // MARK: - Availability

    /// Re-probes every capability. Probes run concurrently and independently:
    /// one hanging probe cannot stop the others from reporting.
    @discardableResult
    public func refresh(now: Date = Date()) async -> [CapabilityStatus] {
        let probes = registry.capabilities
        let results = await withTaskGroup(of: (CapabilityID, CapabilityAvailability).self) { group in
            for capability in probes {
                group.addTask {
                    await (capability.id, capability.availability())
                }
            }
            var collected: [CapabilityID: CapabilityAvailability] = [:]
            for await (id, availability) in group {
                collected[id] = availability
            }
            return collected
        }

        cached = results
        lastRefresh = now
        return statuses()
    }

    /// Current statuses without re-probing. Capabilities that have never been
    /// probed report as temporarily unavailable rather than lying.
    public func statuses() -> [CapabilityStatus] {
        registry.capabilities.map { capability in
            CapabilityStatus(
                metadata: capability.metadata,
                availability: cached[capability.id] ?? .temporarilyUnavailable(reason: "Not yet checked"),
                isEnabled: enabled.contains(capability.id)
            )
        }
    }

    public func status(for id: CapabilityID) -> CapabilityStatus? {
        guard let capability = registry.capability(with: id) else { return nil }
        return CapabilityStatus(
            metadata: capability.metadata,
            availability: cached[id] ?? .temporarilyUnavailable(reason: "Not yet checked"),
            isEnabled: enabled.contains(id)
        )
    }

    /// Statuses worth showing in the UI: unsupported capabilities are hidden
    /// because "Docker: not supported on watchOS" is noise, not information.
    public func discoverableStatuses() -> [CapabilityStatus] {
        statuses().filter(\.availability.isDiscoverable)
    }

    public var lastRefreshDate: Date? {
        lastRefresh
    }

    // MARK: - Enablement

    public func setEnabled(_ isEnabled: Bool, for id: CapabilityID) {
        if isEnabled {
            enabled.insert(id)
        } else {
            enabled.remove(id)
        }
        persistEnablement()
    }

    public func setEnabledCapabilities(_ ids: Set<CapabilityID>) {
        enabled = ids
        persistEnablement()
    }

    public var enabledCapabilities: Set<CapabilityID> {
        enabled
    }

    public func isEnabled(_ id: CapabilityID) -> Bool {
        enabled.contains(id)
    }

    /// The capabilities that will contribute to the next snapshot, paired with
    /// the availability that was observed for them.
    public func collectionPlan(maximumCost: CollectionCost = .high) -> [CapabilityPlanEntry] {
        registry.capabilities.compactMap { capability in
            let availability = cached[capability.id] ?? .temporarilyUnavailable(reason: "Not yet checked")
            guard enabled.contains(capability.id) else {
                return CapabilityPlanEntry(capability: capability, availability: availability, decision: .skipped)
            }
            guard capability.metadata.cost <= maximumCost else {
                return CapabilityPlanEntry(capability: capability, availability: availability, decision: .skipped)
            }
            guard availability.isAvailable else {
                return CapabilityPlanEntry(
                    capability: capability,
                    availability: availability,
                    decision: .placeholder(availability.collectionStatus)
                )
            }
            return CapabilityPlanEntry(capability: capability, availability: availability, decision: .collect)
        }
    }

    private func persistEnablement() {
        enablementStore?.save(
            EnablementRecord(
                enabledIDs: enabled,
                knownIDs: Set(registry.capabilities.map(\.id))
            )
        )
    }
}

/// One capability's role in an upcoming snapshot.
public struct CapabilityPlanEntry: Sendable, Identifiable {
    public enum Decision: Sendable, Hashable {
        /// Run the collector.
        case collect

        /// Record an empty section carrying this status, so the timeline shows
        /// the gap instead of silently omitting the capability.
        case placeholder(CollectionStatus)

        /// The user turned it off; record it as skipped.
        case skipped
    }

    public let capability: AnyCapability
    public let availability: CapabilityAvailability
    public let decision: Decision

    public var id: CapabilityID {
        capability.id
    }

    public init(capability: AnyCapability, availability: CapabilityAvailability, decision: Decision) {
        self.capability = capability
        self.availability = availability
        self.decision = decision
    }
}
