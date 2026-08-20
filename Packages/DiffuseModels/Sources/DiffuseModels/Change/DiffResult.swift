import Foundation

/// Aggregate counts for a diff, precomputed so that summary UI and CLI output
/// never have to re-scan the change list.
public struct DiffSummary: Sendable, Hashable, Codable {
    public let totalChanges: Int
    public let countsBySeverity: [ChangeSeverity: Int]
    public let countsByKind: [ChangeKind: Int]
    public let changedSections: Int
    public let comparedSections: Int

    /// Sections present in one snapshot but not the other — usually a
    /// capability that became available or disappeared between captures.
    public let asymmetricSections: [CapabilityID]

    /// The interval between the two captures.
    public let elapsed: TimeInterval

    public init(
        totalChanges: Int,
        countsBySeverity: [ChangeSeverity: Int],
        countsByKind: [ChangeKind: Int],
        changedSections: Int,
        comparedSections: Int,
        asymmetricSections: [CapabilityID],
        elapsed: TimeInterval
    ) {
        self.totalChanges = totalChanges
        self.countsBySeverity = countsBySeverity
        self.countsByKind = countsByKind
        self.changedSections = changedSections
        self.comparedSections = comparedSections
        self.asymmetricSections = asymmetricSections
        self.elapsed = elapsed
    }

    public var isEmpty: Bool {
        totalChanges == 0
    }

    public func count(_ severity: ChangeSeverity) -> Int {
        countsBySeverity[severity] ?? 0
    }

    public func count(_ kind: ChangeKind) -> Int {
        countsByKind[kind] ?? 0
    }

    public var significantCount: Int {
        count(.significant) + count(.critical)
    }

    /// The most severe change present, or `nil` for an empty diff.
    public var peakSeverity: ChangeSeverity? {
        ChangeSeverity.allCases.reversed().first { count($0) > 0 }
    }

    /// `17 changes` / `1 change` / `No changes`
    public var headline: String {
        switch totalChanges {
        case 0: "No changes"
        case 1: "1 change"
        default: "\(totalChanges) changes"
        }
    }

    public static let empty = DiffSummary(
        totalChanges: 0,
        countsBySeverity: [:],
        countsByKind: [:],
        changedSections: 0,
        comparedSections: 0,
        asymmetricSections: [],
        elapsed: 0
    )
}

/// The differences within one capability's section.
public struct SectionDiff: Sendable, Hashable, Codable, Identifiable {
    public let capability: CapabilityID
    public let displayName: String
    public let category: SectionCategory
    public let symbol: String

    /// Collection status on each side, so the UI can distinguish "nothing
    /// changed" from "we could not look this time".
    public let baseStatus: CollectionStatus?
    public let targetStatus: CollectionStatus?

    public let changes: [Change]

    /// Entities compared that produced no change.
    public let unchangedEntityCount: Int

    public var id: CapabilityID {
        capability
    }

    public init(
        capability: CapabilityID,
        displayName: String,
        category: SectionCategory,
        symbol: String,
        baseStatus: CollectionStatus?,
        targetStatus: CollectionStatus?,
        changes: [Change],
        unchangedEntityCount: Int
    ) {
        self.capability = capability
        self.displayName = displayName
        self.category = category
        self.symbol = symbol
        self.baseStatus = baseStatus
        self.targetStatus = targetStatus
        self.changes = changes
        self.unchangedEntityCount = unchangedEntityCount
    }

    public var isEmpty: Bool {
        changes.isEmpty
    }

    public var peakSeverity: ChangeSeverity? {
        changes.map(\.severity).max()
    }

    /// True when the section could not be compared like-for-like because one
    /// side is missing or failed.
    public var isComparable: Bool {
        (baseStatus?.hasData ?? false) && (targetStatus?.hasData ?? false)
    }

    /// Explains an incomparable section in one line.
    public var incomparableReason: String? {
        guard !isComparable else { return nil }
        switch (baseStatus, targetStatus) {
        case (nil, _?): return "First seen in the later snapshot"
        case (_?, nil): return "Not collected in the later snapshot"
        case let (base?, target?):
            if !base.hasData,
               !target.hasData {
                return "Not collected in either snapshot (\(target.displayName.lowercased()))"
            }
            if !base.hasData {
                return "Not collected in the earlier snapshot (\(base.displayName.lowercased()))"
            }
            return "Not collected in the later snapshot (\(target.displayName.lowercased()))"
        case (nil, nil): return "Not collected"
        }
    }
}

/// A group of changes that happened close together in time.
///
/// Clustering is deterministic temporal analysis, not inference: changes whose
/// observation times fall within a gap threshold of each other are grouped so
/// the user can see "these four things moved together".
public struct ChangeCluster: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let start: Date
    public let end: Date
    public let changeIDs: [ChangeID]
    public let peakSeverity: ChangeSeverity

    /// The capabilities represented in this cluster, in order of appearance.
    public let capabilities: [CapabilityID]

    public init(
        id: String,
        start: Date,
        end: Date,
        changeIDs: [ChangeID],
        peakSeverity: ChangeSeverity,
        capabilities: [CapabilityID]
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.changeIDs = changeIDs
        self.peakSeverity = peakSeverity
        self.capabilities = capabilities
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public var count: Int {
        changeIDs.count
    }

    /// `4 changes over 5 min`
    public var headline: String {
        let countText = count == 1 ? "1 change" : "\(count) changes"
        guard duration >= 1 else { return countText }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        guard let span = formatter.string(from: duration) else { return countText }
        return "\(countText) over \(span)"
    }
}

/// The complete answer to "what changed between these two snapshots".
public struct DiffResult: Sendable, Hashable, Codable, Identifiable {
    public let base: SnapshotReference
    public let target: SnapshotReference
    public let generatedAt: Date
    public let summary: DiffSummary
    public let sectionDiffs: [SectionDiff]
    public let clusters: [ChangeCluster]

    public var id: String {
        "\(base.id.rawValue)..\(target.id.rawValue)"
    }

    public init(
        base: SnapshotReference,
        target: SnapshotReference,
        generatedAt: Date,
        summary: DiffSummary,
        sectionDiffs: [SectionDiff],
        clusters: [ChangeCluster]
    ) {
        self.base = base
        self.target = target
        self.generatedAt = generatedAt
        self.summary = summary
        self.sectionDiffs = sectionDiffs
        self.clusters = clusters
    }

    /// Every change, in deterministic presentation order.
    public var changes: [Change] {
        sectionDiffs.flatMap(\.changes).sortedForPresentation()
    }

    public var isEmpty: Bool {
        summary.isEmpty
    }

    /// Sections that actually contain changes, in presentation order.
    public var changedSections: [SectionDiff] {
        sectionDiffs.filter { !$0.isEmpty }.sorted {
            let left = $0.peakSeverity ?? .informational
            let right = $1.peakSeverity ?? .informational
            if left != right {
                return left > right
            }
            if $0.category != $1.category {
                return $0.category < $1.category
            }
            return $0.displayName < $1.displayName
        }
    }

    public func changes(minimumSeverity: ChangeSeverity) -> [Change] {
        changes.filtered(minimumSeverity: minimumSeverity)
    }

    public func change(id: ChangeID) -> Change? {
        changes.first { $0.id == id }
    }

    public func changes(in cluster: ChangeCluster) -> [Change] {
        let wanted = Set(cluster.changeIDs)
        return changes.filter { wanted.contains($0.id) }
    }

    /// Changes grouped by category, for the sectioned comparison UI.
    public var changesByCategory: [(category: SectionCategory, changes: [Change])] {
        Dictionary(grouping: changes, by: \.category)
            .map { (category: $0.key, changes: $0.value.sortedForPresentation()) }
            .sorted { $0.category < $1.category }
    }
}
