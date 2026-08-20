import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

/// Properties that must hold for generated libraries, not just the examples
/// someone thought to write down. Failures include the seed.
@Suite("Retention invariants")
struct RetentionInvariants {
    private static let seeds: [UInt64] = [1, 7, 42, 1337, 99991, 2_718_281_828]

    @Test("The newest snapshot is never in the deletion list", arguments: seeds)
    func newestSurvives(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let summaries = Self.library(using: &generator)
        let policy = Self.policy(using: &generator)
        let average = Int64(generator.int(in: 1 ... 5000))
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: policy,
            now: SnapshotBuilder.referenceDate,
            averageBytesPerSnapshot: average
        )
        let newest = summaries.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.id < rhs.id
        }.first
        if let newest {
            #expect(!plan.deletions.contains(newest.id), "seed \(seed) deleted the newest snapshot")
        }
        #expect(plan.retainedCount == summaries.count - plan.deletions.count, "seed \(seed)")
        #expect(plan.reclaimedBytes == Int64(plan.deletions.count) * average, "seed \(seed)")
    }

    @Test("Pinned snapshots survive when the policy protects them", arguments: seeds)
    func pinnedSurvive(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let summaries = Self.library(using: &generator)
        let policy = RetentionPolicy(
            age: .days(1),
            maximumBytes: 100,
            maximumCount: 1,
            protectsPinned: true,
            protectsLabelled: true
        )
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: policy,
            now: SnapshotBuilder.referenceDate,
            averageBytesPerSnapshot: 1000
        )
        let newest = summaries.max(by: { $0.capturedAt < $1.capturedAt })?.id
        for summary in summaries where policy.isProtected(summary) && summary.id != newest {
            #expect(!plan.deletions.contains(summary.id), "seed \(seed) deleted protected \(summary.id)")
        }
    }

    @Test("An unlimited policy is a no-op for any library", arguments: seeds)
    func unlimitedIsEmpty(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let plan = RetentionPlanner.plan(
            summaries: Self.library(using: &generator),
            policy: .unlimited,
            now: SnapshotBuilder.referenceDate,
            averageBytesPerSnapshot: 1000
        )
        #expect(plan.isEmpty, "seed \(seed)")
    }

    @Test("Deletion reasons only name snapshots that are actually deleted", arguments: seeds)
    func reasonsMatchDeletions(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let summaries = Self.library(using: &generator)
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: Self.policy(using: &generator),
            now: SnapshotBuilder.referenceDate,
            averageBytesPerSnapshot: 500
        )
        #expect(Set(plan.deletions) == Set(plan.reasons.keys), "seed \(seed)")
    }

    private static func library(using generator: inout SeededGenerator) -> [SnapshotSummary] {
        let count = generator.int(in: 1 ... 24)
        let now = SnapshotBuilder.referenceDate
        return (0 ..< count).map { index in
            .stub(
                id: String(format: "s-%02d-%llu", index, generator.next() % 10000),
                capturedAt: now.addingTimeInterval(-Double(index) * 3600),
                label: generator.bool() ? "keep-\(index)" : nil,
                isPinned: generator.bool() && generator.bool()
            )
        }
    }

    private static func policy(using generator: inout SeededGenerator) -> RetentionPolicy {
        RetentionPolicy(
            age: generator.bool() ? .forever : .days(generator.int(in: 1 ... 90)),
            maximumBytes: generator.bool() ? Int64(generator.int(in: 1 ... 20)) * 1000 : nil,
            maximumCount: generator.bool() ? generator.int(in: 0 ... 8) : nil
        )
    }
}

@Suite("Scheduler invariants")
struct SchedulerInvariants {
    private static let seeds: [UInt64] = [3, 11, 42, 99, 1024, 777_777]

    @Test("A disabled schedule never captures", arguments: seeds)
    func disabledNeverFires(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let last: Date? = generator.bool() ? SnapshotBuilder.referenceDate
            .addingTimeInterval(-Double(generator.int(in: 0 ... 100_000))) : nil
        let decision = SnapshotScheduler.decide(
            schedule: .disabled,
            lastCapture: last,
            now: SnapshotBuilder.referenceDate,
            systemEvent: generator.bool()
        )
        #expect(decision == .disabled, "seed \(seed)")
        #expect(SnapshotScheduler.nextCaptureDate(
            schedule: .disabled,
            lastCapture: last,
            now: SnapshotBuilder.referenceDate
        ) == nil)
    }

    @Test("Waiting until is never in the past", arguments: seeds)
    func waitIsFuture(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let now = SnapshotBuilder.referenceDate
        let last = now.addingTimeInterval(-Double(generator.int(in: 0 ... 20000)))
        let cadence: SnapshotSchedule.Cadence = generator.pick([.hourly, .everyFourHours, .daily, .off])
        let schedule = SnapshotSchedule(
            cadence: cadence,
            capturesOnSystemEvents: generator.bool(),
            minimumInterval: TimeInterval(generator.int(in: 60 ... 3600))
        )
        switch SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: last,
            now: now,
            systemEvent: generator.bool()
        ) {
        case let .wait(until):
            if schedule.cadence.interval != nil {
                #expect(until >= now, "seed \(seed)")
            }
        case .capture, .disabled:
            break
        }
    }

    @Test("shouldCapture matches the capture case exactly", arguments: seeds)
    func shouldCaptureConsistency(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let now = SnapshotBuilder.referenceDate
        let last: Date? = generator.bool() ? now.addingTimeInterval(-Double(generator.int(in: 0 ... 50000))) : nil
        let schedule = SnapshotSchedule(
            cadence: generator.pick([.off, .hourly, .everyFourHours, .daily]),
            capturesOnSystemEvents: generator.bool(),
            minimumInterval: TimeInterval(generator.int(in: 1 ... 3600))
        )
        let decision = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: last,
            now: now,
            systemEvent: generator.bool()
        )
        if case .capture = decision {
            #expect(decision.shouldCapture, "seed \(seed)")
        } else {
            #expect(!decision.shouldCapture, "seed \(seed)")
        }
    }
}

@Suite("Query invariants")
struct QueryInvariants {
    private static let seeds: [UInt64] = [5, 8, 21, 34, 55, 89]

    @Test("Paging never returns more than the limit", arguments: seeds)
    func pagingLimit(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let rows = Self.rows(using: &generator)
        let limit = generator.int(in: 1 ... 8)
        let offset = generator.int(in: 0 ... 6)
        let page = SnapshotQuery(limit: limit, offset: offset).apply(to: rows)
        #expect(page.count <= limit, "seed \(seed)")
        #expect(page.count <= max(0, rows.count - offset), "seed \(seed)")
    }

    @Test("Newest-first and oldest-first are reverse orders of the same set", arguments: seeds)
    func sortReversal(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let rows = Self.rows(using: &generator)
        let newest = SnapshotQuery(sort: .newestFirst).apply(to: rows)
        let oldest = SnapshotQuery(sort: .oldestFirst).apply(to: rows)
        #expect(newest.map(\.id) == oldest.map(\.id).reversed(), "seed \(seed)")
    }

    @Test("Applying all twice is stable", arguments: seeds)
    func stability(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let rows = Self.rows(using: &generator)
        #expect(SnapshotQuery.all.apply(to: rows) == SnapshotQuery.all.apply(to: rows), "seed \(seed)")
    }

    private static func rows(using generator: inout SeededGenerator) -> [SnapshotSummary] {
        let now = SnapshotBuilder.referenceDate
        return (0 ..< generator.int(in: 3 ... 20)).map { index in
            .stub(
                id: "q-\(index)-\(generator.next() % 1000)",
                capturedAt: now.addingTimeInterval(-Double(index) * 60),
                platform: generator.pick(Platform.all),
                origin: generator.pick(SnapshotOrigin.allCases),
                isPinned: generator.bool(),
                tags: generator.bool() ? ["work"] : []
            )
        }
    }
}
