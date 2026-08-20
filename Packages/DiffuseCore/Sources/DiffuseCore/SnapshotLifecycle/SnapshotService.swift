import DiffuseCapabilities
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import Foundation

/// The one façade every app talks to.
///
/// View models on four platforms should not each re-derive "capture, then
/// save, then diff against the previous one, then apply retention". That
/// sequence is product behaviour, so it lives here, once, and the platform
/// layers stay thin enough to be genuinely native without duplicating logic.
public actor SnapshotService {
    private let coordinator: SnapshotCoordinator
    private let store: any SnapshotStore
    private let catalog: CapabilityCatalog
    private let timeSource: any TimeSource

    public private(set) var diffOptions: DiffOptions
    public private(set) var retentionPolicy: RetentionPolicy

    public init(
        coordinator: SnapshotCoordinator,
        store: any SnapshotStore,
        catalog: CapabilityCatalog,
        timeSource: any TimeSource = SystemTimeSource(),
        diffOptions: DiffOptions = .default,
        retentionPolicy: RetentionPolicy = .default
    ) {
        self.coordinator = coordinator
        self.store = store
        self.catalog = catalog
        self.timeSource = timeSource
        self.diffOptions = diffOptions
        self.retentionPolicy = retentionPolicy
    }

    // MARK: - Configuration

    public func setDiffOptions(_ options: DiffOptions) {
        diffOptions = options
    }

    public func setRetentionPolicy(_ policy: RetentionPolicy) {
        retentionPolicy = policy
    }

    // MARK: - Capture

    /// Captures, persists and prunes in one step.
    ///
    /// Retention runs after the save rather than before, so the new snapshot is
    /// always the one that survives a tight storage limit.
    @discardableResult
    public func capture(
        origin: SnapshotOrigin = .manual,
        label: String? = nil,
        note: String? = nil,
        tags: Set<String> = [],
        isBackground: Bool = false,
        skipIfUnchanged: Bool = false
    ) async throws -> CaptureReport {
        let report = await coordinator.capture(
            origin: origin,
            label: label,
            note: note,
            tags: tags,
            isBackground: isBackground
        )
        if skipIfUnchanged, origin != .manual, origin != .imported,
           let latest = try await store.latest() {
            let diff = DiffEngine(options: diffOptions).diff(base: latest, target: report.snapshot)
            if diff.summary.totalChanges == 0 {
                return CaptureReport(
                    snapshot: report.snapshot,
                    outcomes: report.outcomes,
                    totalDuration: report.totalDuration,
                    didPersist: false
                )
            }
        }
        try await store.save(report.snapshot)
        try await store.applyRetention(retentionPolicy, now: timeSource.now)
        return report
    }

    // MARK: - Reading

    public func summaries(matching query: SnapshotQuery = .all) async throws -> [SnapshotSummary] {
        try await store.summaries(matching: query)
    }

    public func snapshot(id: SnapshotID) async throws -> Snapshot? {
        try await store.snapshot(id: id)
    }

    public func latest() async throws -> Snapshot? {
        try await store.latest()
    }

    public func count() async throws -> Int {
        try await store.count()
    }

    public func storageSize() async throws -> Int64 {
        try await store.storageSize()
    }

    public func snapshots(matching query: SnapshotQuery = .all) async throws -> [Snapshot] {
        try await store.snapshots(matching: query)
    }

    public func search(_ query: String, limit: Int = 40) async throws -> [SearchResult] {
        try await SearchIndex(snapshots: store.snapshots(matching: .all)).search(query, limit: limit)
    }

    public func annotate(id: SnapshotID, with annotation: SnapshotAnnotation) async throws {
        try await store.annotate(id: id, with: annotation)
    }

    public func delete(id: SnapshotID) async throws {
        try await store.delete(id: id)
    }

    public func deleteAll() async throws {
        try await store.deleteAll()
    }

    // MARK: - Comparison

    public func diff(base: SnapshotID, target: SnapshotID, options: DiffOptions? = nil) async throws -> DiffResult {
        let baseSnapshot = try await store.require(id: base)
        let targetSnapshot = try await store.require(id: target)
        return DiffEngine(options: options ?? diffOptions).diff(base: baseSnapshot, target: targetSnapshot)
    }

    /// The diff between the two most recent snapshots, or `nil` when fewer than
    /// two exist.
    public func latestDiff(options: DiffOptions? = nil) async throws -> DiffResult? {
        guard let pair = try await store.latestPair() else { return nil }
        return DiffEngine(options: options ?? diffOptions).diff(base: pair.base, target: pair.target)
    }

    public func timeline(matching query: SnapshotQuery = .all,
                         options: DiffOptions? = nil) async throws -> ChangeTimeline {
        let snapshots = try await store.snapshots(matching: query)
        return ChangeTimeline(snapshots: snapshots, options: options ?? diffOptions)
    }

    // MARK: - Capabilities

    @discardableResult
    public func refreshCapabilities() async -> [CapabilityStatus] {
        await catalog.refresh(now: timeSource.now)
    }

    public func capabilityStatuses() async -> [CapabilityStatus] {
        await catalog.discoverableStatuses()
    }

    public func setCapabilityEnabled(_ isEnabled: Bool, for id: CapabilityID) async {
        await catalog.setEnabled(isEnabled, for: id)
    }

    public func privacyLedger() async -> PrivacyLedger {
        await PrivacyLedger(statuses: catalog.statuses())
    }

    // MARK: - Overview

    /// The at-a-glance state the Overview screen shows on every platform.
    public func overview(recentLimit: Int = 25) async throws -> Overview {
        let summaries = try await store.summaries(matching: SnapshotQuery(limit: recentLimit))
        guard let newest = summaries.first else {
            return Overview(
                latest: nil,
                previous: nil,
                summary: .empty,
                topChanges: [],
                clusters: [],
                clusterChanges: [],
                snapshotCount: 0,
                capabilityCount: catalog.capabilities.count
            )
        }

        guard summaries.count > 1, let pair = try await store.latestPair() else {
            return try await Overview(
                latest: newest,
                previous: nil,
                summary: .empty,
                topChanges: [],
                clusters: [],
                clusterChanges: [],
                snapshotCount: store.count(),
                capabilityCount: catalog.capabilities.count
            )
        }

        let diff = DiffEngine(options: diffOptions).diff(base: pair.base, target: pair.target)
        let clusteredIDs = Set(diff.clusters.flatMap(\.changeIDs))
        return try await Overview(
            latest: newest,
            previous: summaries.dropFirst().first,
            summary: diff.summary,
            topChanges: Array(diff.changes.prefix(6)),
            clusters: diff.clusters,
            clusterChanges: diff.changes.filter { clusteredIDs.contains($0.id) },
            snapshotCount: store.count(),
            capabilityCount: catalog.capabilities.count
        )
    }

    public struct Overview: Sendable {
        public let latest: SnapshotSummary?
        public let previous: SnapshotSummary?
        public let summary: DiffSummary
        public let topChanges: [Change]
        public let clusters: [ChangeCluster]
        /// Changes that belong to `clusters`, so overview UI never has to
        /// borrow the user's currently selected comparison.
        public let clusterChanges: [Change]
        public let snapshotCount: Int
        public let capabilityCount: Int

        public var hasComparison: Bool {
            previous != nil
        }

        public func changes(in cluster: ChangeCluster) -> [Change] {
            let wanted = Set(cluster.changeIDs)
            return clusterChanges.filter { wanted.contains($0.id) }
        }
    }

    // MARK: - Import & export

    /// Imports a snapshot captured on another device. The origin is rewritten
    /// so an imported snapshot is never mistaken for one taken here.
    @discardableResult
    public func importSnapshot(from data: Data) async throws -> Snapshot {
        let decoded = try SnapshotCoding.decodeSnapshot(data)
        let imported = Snapshot(
            id: SnapshotID(),
            schemaVersion: decoded.schemaVersion,
            capturedAt: decoded.capturedAt,
            platform: decoded.platform,
            device: decoded.device,
            origin: .imported,
            label: decoded.label,
            note: decoded.note,
            isPinned: decoded.isPinned,
            tags: decoded.tags.union(["imported"]),
            sections: decoded.sections,
            metadata: decoded.metadata
        )
        try await store.save(imported)
        return imported
    }

    public func exportSnapshot(id: SnapshotID, redaction: RedactionPolicy = .standard) async throws -> Data {
        let snapshot = try await store.require(id: id)
        return try SnapshotCoding.encode(snapshot.redacted(redaction))
    }

    public func exportDiff(
        base: SnapshotID,
        target: SnapshotID,
        redaction: RedactionPolicy = .standard
    ) async throws -> Data {
        let baseSnapshot = try await store.require(id: base).redacted(redaction)
        let targetSnapshot = try await store.require(id: target).redacted(redaction)
        return try SnapshotCoding.encode(
            DiffEngine(options: diffOptions).diff(base: baseSnapshot, target: targetSnapshot)
        )
    }

    public func exportReport(
        base: SnapshotID,
        target: SnapshotID,
        minimumSeverity: ChangeSeverity = .informational,
        redaction: RedactionPolicy = .standard
    ) async throws -> String {
        let baseSnapshot = try await store.require(id: base).redacted(redaction)
        let targetSnapshot = try await store.require(id: target).redacted(redaction)
        return ReportRenderer.markdown(
            for: DiffEngine(options: diffOptions).diff(base: baseSnapshot, target: targetSnapshot),
            minimumSeverity: minimumSeverity
        )
    }
}
