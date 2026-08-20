import DiffuseCapabilities
import DiffuseModels
import Foundation

/// The outcome of running one capability during a capture.
public struct CollectionOutcome: Sendable, Identifiable {
    public enum Result: Sendable, Hashable {
        case collected(entityCount: Int)
        case placeholder(CollectionStatus)
        case skipped
        case failed(CollectorError)
    }

    public let capability: CapabilityID
    public let displayName: String
    public let result: Result
    public let duration: TimeInterval

    public var id: CapabilityID {
        capability
    }

    public var status: CollectionStatus {
        switch result {
        case .collected: .collected
        case let .placeholder(status): status
        case .skipped: .skipped
        case let .failed(error): error.status
        }
    }

    public var symbol: String {
        status.symbol
    }
}

/// Everything a capture produced, including the parts that did not work.
public struct CaptureReport: Sendable {
    public let snapshot: Snapshot
    public let outcomes: [CollectionOutcome]
    public let totalDuration: TimeInterval
    /// `false` when an automatic capture was discarded because nothing changed.
    public let didPersist: Bool

    public init(
        snapshot: Snapshot,
        outcomes: [CollectionOutcome],
        totalDuration: TimeInterval,
        didPersist: Bool = true
    ) {
        self.snapshot = snapshot
        self.outcomes = outcomes.sorted { $0.capability < $1.capability }
        self.totalDuration = totalDuration
        self.didPersist = didPersist
    }

    public var succeeded: [CollectionOutcome] {
        outcomes.filter {
            if case .collected = $0.result {
                true
            } else {
                false
            }
        }
    }

    public var problems: [CollectionOutcome] {
        outcomes.filter(\.status.isProblem)
    }

    /// The slowest collectors, for the diagnostics screen.
    public func slowest(_ count: Int) -> [CollectionOutcome] {
        Array(outcomes.sorted { $0.duration > $1.duration }.prefix(count))
    }
}

/// Runs every available collector and assembles a snapshot.
///
/// Two rules define this type. Collectors run **concurrently**, because a
/// snapshot that takes as long as the sum of its parts is a snapshot nobody
/// takes. And collectors are **isolated**: a throw, a hang or a permission
/// denial produces a section that records what went wrong instead of failing
/// the capture. A snapshot with eleven good sections and one timeout is far
/// more useful than no snapshot at all.
public actor SnapshotCoordinator {
    private let catalog: CapabilityCatalog
    private let deviceProvider: any DeviceIdentityProviding
    private let timeSource: any TimeSource
    private let appVersion: SemanticVersion
    private let platform: Platform

    public init(
        catalog: CapabilityCatalog,
        deviceProvider: any DeviceIdentityProviding,
        platform: Platform,
        timeSource: any TimeSource = SystemTimeSource(),
        appVersion: SemanticVersion = "1.0.0"
    ) {
        self.catalog = catalog
        self.deviceProvider = deviceProvider
        self.platform = platform
        self.timeSource = timeSource
        self.appVersion = appVersion
    }

    /// Captures a snapshot.
    ///
    /// Never throws. Any failure a collector can produce is representable in
    /// the resulting snapshot, which is what makes the capture button safe to
    /// press at any time.
    public func capture(
        origin: SnapshotOrigin = .manual,
        label: String? = nil,
        note: String? = nil,
        tags: Set<String> = [],
        isBackground: Bool = false,
        maximumCost: CollectionCost? = nil,
        refreshAvailability: Bool = true
    ) async -> CaptureReport {
        let startedAt = timeSource.now
        let clockStart = ContinuousClock.now

        if refreshAvailability {
            await catalog.refresh(now: startedAt)
        }

        // Background captures skip anything expensive: iOS gives a background
        // task seconds, not minutes, and a partial snapshot beats a killed one.
        let costCeiling = maximumCost ?? (isBackground ? .low : .high)
        let plan = await catalog.collectionPlan(maximumCost: costCeiling)

        var sections: [SnapshotSection] = []
        var outcomes: [CollectionOutcome] = []
        var skipped: [CapabilityID] = []

        for entry in plan {
            switch entry.decision {
            case .collect:
                continue
            case let .placeholder(status):
                sections.append(
                    entry.capability.placeholder(
                        status: status,
                        at: startedAt,
                        diagnostics: entry.availability.detail.map { [Diagnostic.info($0)] } ?? []
                    )
                )
                outcomes.append(
                    CollectionOutcome(
                        capability: entry.capability.id,
                        displayName: entry.capability.metadata.displayName,
                        result: .placeholder(status),
                        duration: 0
                    )
                )
            case .skipped:
                skipped.append(entry.capability.id)
                sections.append(entry.capability.placeholder(status: .skipped, at: startedAt))
                outcomes.append(
                    CollectionOutcome(
                        capability: entry.capability.id,
                        displayName: entry.capability.metadata.displayName,
                        result: .skipped,
                        duration: 0
                    )
                )
            }
        }

        let runnable = plan.filter {
            if case .collect = $0.decision {
                true
            } else {
                false
            }
        }
        let collected = await runCollectors(
            runnable,
            startedAt: startedAt,
            origin: origin,
            isBackground: isBackground
        )
        sections.append(contentsOf: collected.map(\.section))
        outcomes.append(contentsOf: collected.map(\.outcome))

        let totalDuration = (ContinuousClock.now - clockStart).seconds

        let snapshot = Snapshot(
            schemaVersion: .current,
            capturedAt: startedAt,
            platform: platform,
            device: deviceProvider.deviceIdentity(),
            origin: origin,
            label: label,
            note: note,
            isPinned: false,
            tags: tags,
            sections: sections.sorted { $0.capability < $1.capability },
            metadata: SnapshotMetadata(
                appVersion: appVersion,
                collectionDuration: totalDuration,
                appliedRedaction: .none,
                skippedCapabilities: skipped.sorted()
            )
        )

        return CaptureReport(snapshot: snapshot, outcomes: outcomes, totalDuration: totalDuration)
    }

    // MARK: - Collection

    private struct CollectorRun: Sendable {
        let section: SnapshotSection
        let outcome: CollectionOutcome
    }

    private func runCollectors(
        _ entries: [CapabilityPlanEntry],
        startedAt: Date,
        origin: SnapshotOrigin,
        isBackground: Bool
    ) async -> [CollectorRun] {
        await withTaskGroup(of: CollectorRun.self) { group in
            for entry in entries {
                let capability = entry.capability
                let deadline = capability.metadata.cost.defaultTimeout
                let context = CollectionContext(
                    startedAt: startedAt,
                    platform: platform,
                    origin: origin,
                    deadline: deadline,
                    isBackground: isBackground
                )

                group.addTask {
                    let clockStart = ContinuousClock.now
                    do {
                        let section = try await withDeadline(deadline) {
                            try await capability.collect(context: context)
                        }
                        let elapsed = (ContinuousClock.now - clockStart).seconds
                        return CollectorRun(
                            section: section,
                            outcome: CollectionOutcome(
                                capability: capability.id,
                                displayName: capability.metadata.displayName,
                                result: .collected(entityCount: section.entityCount),
                                duration: elapsed
                            )
                        )
                    } catch {
                        let elapsed = (ContinuousClock.now - clockStart).seconds
                        let collectorError = (error as? CollectorError) ?? .underlying(String(describing: error))
                        return CollectorRun(
                            section: capability.placeholder(
                                status: collectorError.status,
                                at: startedAt,
                                diagnostics: [
                                    Diagnostic(
                                        level: collectorError.status == .timedOut ? .warning : .error,
                                        message: collectorError.message,
                                        detail: "Collector \(capability.id) after \(String(format: "%.2f", elapsed))s"
                                    ),
                                ]
                            ),
                            outcome: CollectionOutcome(
                                capability: capability.id,
                                displayName: capability.metadata.displayName,
                                result: .failed(collectorError),
                                duration: elapsed
                            )
                        )
                    }
                }
            }

            var runs: [CollectorRun] = []
            for await run in group {
                runs.append(run)
            }
            return runs
        }
    }
}

/// Races an operation against a deadline.
///
/// The losing task is cancelled, so a well-behaved collector stops immediately.
/// A collector that ignores cancellation is abandoned rather than waited on —
/// the point of the deadline is that one badly behaved subprocess cannot hold
/// the whole snapshot hostage.
func withDeadline<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw CollectorError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw CollectorError.timedOut
        }
        return result
    }
}

extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
