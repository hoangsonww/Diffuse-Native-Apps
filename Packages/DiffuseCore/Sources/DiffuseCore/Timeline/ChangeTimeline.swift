import DiffuseDiff
import DiffuseModels
import Foundation

/// Diffs a run of snapshots pairwise and correlates the results.
///
/// A single diff answers "what changed between these two points". A timeline
/// answers "when did each thing change, and what moved together" — which is
/// what turns a list of differences into an explanation. Still no inference:
/// each change is stamped with the capture time of the snapshot that first
/// showed it, and clustering is plain interval grouping.
public struct ChangeTimeline: Sendable {
    /// One entry in the timeline: a snapshot and what changed relative to its
    /// predecessor.
    public struct Step: Sendable, Identifiable {
        public let base: SnapshotReference
        public let target: SnapshotReference
        public let diff: DiffResult

        public var id: String {
            diff.id
        }

        public var date: Date {
            target.capturedAt
        }

        public var changeCount: Int {
            diff.summary.totalChanges
        }
    }

    public let steps: [Step]
    public let clusters: [ChangeCluster]

    /// The oldest and newest snapshots in the range.
    public let range: ClosedRange<Date>?

    public init(snapshots: [Snapshot], options: DiffOptions = .default) {
        let ordered = snapshots.sorted { $0.capturedAt < $1.capturedAt }
        let engine = DiffEngine(options: options)

        var steps: [Step] = []
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            let diff = engine.diff(base: previous, target: current)
            steps.append(Step(base: previous.reference, target: current.reference, diff: diff))
        }

        self.steps = steps

        // Cluster across the whole timeline rather than per step, so a Node
        // update at 11:42 and a Docker stop at 11:46 land in the same group
        // even though they were seen in different snapshots.
        let allChanges = steps.flatMap(\.diff.changes)
        clusters = ChangeCorrelator.cluster(
            allChanges,
            window: options.correlationWindow,
            minimumSize: options.minimumClusterSize
        )

        if let first = ordered.first?.capturedAt, let last = ordered.last?.capturedAt, first <= last {
            range = first ... last
        } else {
            range = nil
        }
    }

    public var totalChanges: Int {
        steps.reduce(0) { $0 + $1.changeCount }
    }

    public var allChanges: [Change] {
        steps.flatMap(\.diff.changes).sortedForPresentation()
    }

    /// Every change affecting one entity, oldest first. This is the "history of
    /// this thing" view: how a Node version, a Wi-Fi network or a Git branch
    /// moved over the whole retained window.
    public func history(of identity: EntityIdentity) -> [Change] {
        steps
            .flatMap(\.diff.changes)
            .filter { $0.entity.identity == identity }
            .sorted { $0.observedAt < $1.observedAt }
    }

    /// Change counts bucketed by day, for the timeline's activity strip.
    public func dailyActivity(calendar: Calendar = .current) -> [(day: Date, count: Int)] {
        Dictionary(grouping: steps) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, count: $0.value.reduce(0) { $0 + $1.changeCount }) }
            .sorted { $0.day < $1.day }
    }

    /// The capabilities that changed most often, for the overview screen.
    public func mostActiveCapabilities(limit: Int = 5) -> [(capability: CapabilityID, name: String, count: Int)] {
        var counts: [CapabilityID: (name: String, count: Int)] = [:]
        for change in steps.flatMap(\.diff.changes) {
            let existing = counts[change.capability]
            counts[change.capability] = (name: change.sectionName, count: (existing?.count ?? 0) + 1)
        }
        return counts
            .map { (capability: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.capability < $1.capability
            }
            .prefix(limit)
            .map(\.self)
    }
}
