import DiffuseModels
import Foundation

/// How long snapshots are kept and how much space they may use.
public struct RetentionPolicy: Sendable, Hashable, Codable {
    public enum Age: Sendable, Hashable, Codable, CaseIterable {
        case forever
        case days(Int)

        public static var allCases: [Age] {
            [.forever, .days(30), .days(90), .days(365)]
        }

        public var displayName: String {
            switch self {
            case .forever: "Forever"
            case let .days(count) where count % 365 == 0: count == 365 ? "1 year" : "\(count / 365) years"
            case let .days(count): "\(count) days"
            }
        }

        public var interval: TimeInterval? {
            switch self {
            case .forever: nil
            case let .days(count): TimeInterval(count) * 86400
            }
        }
    }

    public var age: Age

    /// Maximum bytes on disk, or `nil` for no limit.
    public var maximumBytes: Int64?

    /// Maximum number of snapshots, or `nil` for no limit.
    public var maximumCount: Int?

    /// Pinned snapshots and those the user has named are never deleted
    /// automatically. Retention should never eat the snapshot someone
    /// deliberately labelled "before the upgrade".
    public var protectsPinned: Bool
    public var protectsLabelled: Bool

    public init(
        age: Age = .days(90),
        maximumBytes: Int64? = 1_073_741_824,
        maximumCount: Int? = nil,
        protectsPinned: Bool = true,
        protectsLabelled: Bool = true
    ) {
        self.age = age
        self.maximumBytes = maximumBytes
        self.maximumCount = maximumCount
        self.protectsPinned = protectsPinned
        self.protectsLabelled = protectsLabelled
    }

    public static let `default` = RetentionPolicy()
    public static let unlimited = RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: nil)

    public func isProtected(_ summary: SnapshotSummary) -> Bool {
        if protectsPinned, summary.isPinned {
            return true
        }
        if protectsLabelled, let label = summary.label, !label.isEmpty {
            return true
        }
        return false
    }
}

/// Decides which snapshots retention should remove.
///
/// Kept as a pure function over summaries so the decision can be previewed in
/// the UI ("this will delete 14 snapshots") and unit tested without touching a
/// filesystem.
public enum RetentionPlanner {
    public struct Plan: Sendable, Hashable {
        public let deletions: [SnapshotID]
        public let reasons: [SnapshotID: Reason]
        public let retainedCount: Int
        public let reclaimedBytes: Int64

        public var isEmpty: Bool {
            deletions.isEmpty
        }
    }

    public enum Reason: String, Sendable, Hashable, Codable {
        case tooOld
        case overCountLimit
        case overSizeLimit

        public var displayName: String {
            switch self {
            case .tooOld: "Older than the retention window"
            case .overCountLimit: "Beyond the snapshot limit"
            case .overSizeLimit: "Beyond the storage limit"
            }
        }
    }

    public static func plan(
        summaries: [SnapshotSummary],
        policy: RetentionPolicy,
        now: Date,
        averageBytesPerSnapshot: Int64
    ) -> Plan {
        // Newest first: everything below is expressed as "keep the head".
        let ordered = summaries.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.id < rhs.id
        }

        var reasons: [SnapshotID: Reason] = [:]

        if let interval = policy.age.interval {
            let cutoff = now.addingTimeInterval(-interval)
            for summary in ordered where summary.capturedAt < cutoff && !policy.isProtected(summary) {
                reasons[summary.id] = .tooOld
            }
        }

        if let maximumCount = policy.maximumCount {
            var kept = 0
            for summary in ordered {
                if reasons[summary.id] != nil {
                    continue
                }
                if policy.isProtected(summary) {
                    continue
                }
                kept += 1
                if kept > maximumCount {
                    reasons[summary.id] = .overCountLimit
                }
            }
        }

        if let maximumBytes = policy.maximumBytes, averageBytesPerSnapshot > 0 {
            let allowance = max(Int(maximumBytes / averageBytesPerSnapshot), 1)
            var kept = 0
            for summary in ordered {
                if reasons[summary.id] != nil {
                    continue
                }
                if policy.isProtected(summary) {
                    continue
                }
                kept += 1
                if kept > allowance {
                    reasons[summary.id] = .overSizeLimit
                }
            }
        }

        // Always keep the most recent snapshot: without it there is nothing to
        // compare the next one against, which would defeat the entire product.
        if let newest = ordered.first {
            reasons.removeValue(forKey: newest.id)
        }

        let deletions = ordered.map(\.id).filter { reasons[$0] != nil }

        return Plan(
            deletions: deletions,
            reasons: reasons,
            retainedCount: ordered.count - deletions.count,
            reclaimedBytes: Int64(deletions.count) * averageBytesPerSnapshot
        )
    }
}

public extension SnapshotStore {
    /// Applies a retention policy, returning the plan that was executed.
    @discardableResult
    func applyRetention(_ policy: RetentionPolicy, now: Date = Date()) async throws -> RetentionPlanner.Plan {
        let summaries = try await allSummaries()
        guard !summaries.isEmpty else {
            return RetentionPlanner.Plan(deletions: [], reasons: [:], retainedCount: 0, reclaimedBytes: 0)
        }

        let totalBytes = try await storageSize()
        let average = max(totalBytes / Int64(summaries.count), 1)
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: policy,
            now: now,
            averageBytesPerSnapshot: average
        )

        for id in plan.deletions {
            try await delete(id: id)
        }
        return plan
    }
}
