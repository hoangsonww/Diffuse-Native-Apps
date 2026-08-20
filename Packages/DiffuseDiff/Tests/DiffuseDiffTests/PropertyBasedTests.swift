import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

/// Invariants checked against generated input rather than hand-picked examples.
///
/// Example-based tests prove that the cases someone thought of work. These
/// prove properties that must hold for *all* inputs, which is where a semantic
/// diff engine tends to break: an ordering assumption, a mutation that leaks
/// between runs, an identity that is not actually stable.
///
/// The generator is seeded, so a failure is reproducible from the seed printed
/// in the failure message rather than being a flake.
@Suite("Diff engine properties")
struct PropertyBasedDiffTests {
    private let engine = DiffEngine()
    private static let seeds: [UInt64] = [1, 7, 42, 1337, 99991, 2_718_281_828]

    @Test("diff(A, A) is empty for any generated snapshot", arguments: seeds)
    func selfDiffIsAlwaysEmpty(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let snapshot = Self.makeSnapshot(using: &generator, id: "seed-\(seed)")

        let result = engine.selfDiff(snapshot)
        #expect(result.isEmpty, "diff(A, A) must be empty for seed \(seed)")
    }

    @Test("Shuffling entities never changes the diff", arguments: seeds)
    func shufflingIsIrrelevant(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)

        let straight = engine.diff(base: base, target: target)
        let shuffled = engine.diff(
            base: Self.shufflingEntities(of: base, using: &generator),
            target: Self.shufflingEntities(of: target, using: &generator)
        )

        #expect(straight.summary.totalChanges == shuffled.summary.totalChanges, "seed \(seed)")
        #expect(straight.changes.map(\.id) == shuffled.changes.map(\.id), "seed \(seed)")
    }

    @Test("Diffing is repeatable within a process", arguments: seeds)
    func repeatedDiffsAgree(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)

        let results = (0 ..< 5).map { _ in engine.diff(base: base, target: target) }
        #expect(Set(results.map(\.summary.totalChanges)).count == 1, "seed \(seed)")
        #expect(results.allSatisfy { $0 == results[0] }, "seed \(seed)")
    }

    @Test("Added and removed counts mirror when the diff is reversed", arguments: seeds)
    func reversalMirrorsCounts(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)

        let forward = engine.diff(base: base, target: target)
        let backward = engine.diff(base: target, target: base)

        #expect(forward.summary.count(.added) == backward.summary.count(.removed), "seed \(seed)")
        #expect(forward.summary.count(.removed) == backward.summary.count(.added), "seed \(seed)")
        #expect(forward.summary.count(.modified) == backward.summary.count(.modified), "seed \(seed)")
    }

    @Test("Every reported change names an entity that exists on the relevant side", arguments: seeds)
    func changesReferenceRealEntities(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)

        let baseIdentities = Set(base.sections.flatMap(\.allEntities).map(\.identity))
        let targetIdentities = Set(target.sections.flatMap(\.allEntities).map(\.identity))

        for change in engine.diff(base: base, target: target).changes {
            // Synthetic section-level carriers are not real entities.
            guard change.entity.identity.kind == TestSchema.widget else { continue }
            switch change.kind {
            case .added:
                #expect(targetIdentities.contains(change.entity.identity), "seed \(seed)")
            case .removed:
                #expect(baseIdentities.contains(change.entity.identity), "seed \(seed)")
            case .modified, .unchanged:
                #expect(baseIdentities.contains(change.entity.identity), "seed \(seed)")
                #expect(targetIdentities.contains(change.entity.identity), "seed \(seed)")
            }
        }
    }

    @Test("Severity filtering is monotonic", arguments: seeds)
    func severityFilteringIsMonotonic(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)
        let result = engine.diff(base: base, target: target)

        var previous = Int.max
        for severity in ChangeSeverity.allCases {
            let count = result.changes(minimumSeverity: severity).count
            #expect(count <= previous, "Raising the threshold must never reveal more changes (seed \(seed))")
            previous = count
        }
    }

    @Test("Summary counts always agree with the change list", arguments: seeds)
    func summaryMatchesChanges(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let base = Self.makeSnapshot(using: &generator, id: "base-\(seed)")
        let target = Self.makeSnapshot(using: &generator, id: "target-\(seed)", at: 3600)
        let result = engine.diff(base: base, target: target)

        let reported = result.changes.filter { $0.kind != .unchanged }
        #expect(result.summary.totalChanges == reported.count, "seed \(seed)")

        for severity in ChangeSeverity.allCases {
            let actual = reported.count { $0.severity == severity }
            #expect(result.summary.count(severity) == actual, "seed \(seed), \(severity)")
        }
    }

    // MARK: - Generation

    private static func makeSnapshot(
        using generator: inout SeededGenerator,
        id: String,
        at offset: TimeInterval = 0
    ) -> Snapshot {
        let date = SnapshotBuilder.referenceDate.addingTimeInterval(offset)
        let entityCount = generator.int(in: 0 ... 12)

        let entities = (0 ..< entityCount).map { index -> SnapshotEntity in
            TestSchema.entity(
                "entity-\(generator.int(in: 0 ... 15))-\(index % 4)",
                value: .string("value-\(generator.int(in: 0 ... 5))"),
                version: "\(generator.int(in: 0 ... 3)).\(generator.int(in: 0 ... 9)).\(generator.int(in: 0 ... 9))",
                size: Int64(generator.int(in: 0 ... 100_000))
            )
        }

        // Duplicate identities are possible by construction; normalization is
        // expected to collapse them rather than produce a corrupt diff.
        var seen = Set<EntityIdentity>()
        let unique = entities.filter { seen.insert($0.identity).inserted }

        return SnapshotBuilder(id: id, capturedAt: date)
            .adding(TestSchema.section(
                entities: unique,
                at: date,
                attributes: ["total": .integer(Int64(unique.count))]
            ))
            .build()
    }

    private static func shufflingEntities(
        of snapshot: Snapshot,
        using generator: inout SeededGenerator
    ) -> Snapshot {
        var copy = snapshot
        copy.sections = snapshot.sections.map { section in
            var section = section
            section.entities = generator.shuffled(section.entities)
            return section
        }
        return copy
    }
}
