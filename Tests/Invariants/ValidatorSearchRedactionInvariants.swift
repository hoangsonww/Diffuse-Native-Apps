import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Validator invariants")
struct ValidatorInvariants {
    private static let seeds: [UInt64] = [2, 9, 16, 25, 36, 49]

    @Test("A generated well-formed snapshot always validates", arguments: seeds)
    func wellFormedValidates(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let snapshot = Self.makeSnapshot(using: &generator)
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.isEmpty, "seed \(seed): \(problems.joined(separator: "; "))")
    }

    @Test("A valid snapshot round-trips through JSON unchanged", arguments: seeds)
    func roundTrip(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let snapshot = Self.makeSnapshot(using: &generator)
        let encoded = try SnapshotCoding.encode(snapshot)
        let decoded = try SnapshotCoding.decodeSnapshot(encoded)
        #expect(decoded == snapshot, "seed \(seed)")
        #expect(try SnapshotCoding.encode(decoded) == encoded, "seed \(seed)")
    }

    @Test("An unknown property is always reported", arguments: seeds)
    func unknownProperty(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        var snapshot = Self.makeSnapshot(using: &generator)
        guard !snapshot.sections.isEmpty, !snapshot.sections[0].entities.isEmpty else { return }
        snapshot.sections[0].entities[0][PropertyKey("mystery-\(seed)")] = .string("x")
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("mystery-\(seed)") }, "seed \(seed)")
    }

    private static func makeSnapshot(using generator: inout SeededGenerator) -> Snapshot {
        let count = generator.int(in: 1 ... 6)
        let entities = (0 ..< count).map { index in
            TestSchema.entity(
                "e-\(index)",
                name: "Widget \(index)",
                value: .string("v\(generator.int(in: 0 ... 9))"),
                version: "1.\(generator.int(in: 0 ... 5)).\(generator.int(in: 0 ... 9))",
                size: Int64(generator.int(in: 1 ... 10000))
            )
        }
        return SnapshotBuilder(id: "inv-\(generator.next() % 1_000_000)")
            .on(generator.pick(Platform.all))
            .originating(generator.pick(SnapshotOrigin.allCases))
            .withWidgets(entities)
            .build()
    }
}

@Suite("Search invariants")
struct SearchInvariants {
    private static let seeds: [UInt64] = [4, 14, 24, 34, 44, 54]

    @Test("Searching for an entity's own name finds it", arguments: seeds)
    func findsOwnName(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let name = "UniqueToken\(generator.next() % 10000)"
        let snapshot = SnapshotBuilder()
            .withWidgets([TestSchema.entity("one", name: name, value: .string("x"))])
            .build()
        let results = SearchIndex(snapshots: [snapshot]).search(name)
        #expect(results.contains { $0.title == name }, "seed \(seed)")
    }

    @Test("Raising the limit never drops earlier hits", arguments: seeds)
    func limitMonotonic(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let snapshots = (0 ..< 12).map { index in
            SnapshotBuilder(id: "s\(index)")
                .withWidgets([TestSchema.entity("e\(index)", name: "Shared \(index)", value: .string("needle"))])
                .build()
        }
        let index = SearchIndex(snapshots: snapshots)
        let small = index.search("needle", limit: 3)
        let large = index.search("needle", limit: 10)
        #expect(small.count <= large.count, "seed \(seed)")
        #expect(Array(large.prefix(small.count)).map(\.id) == small.map(\.id), "seed \(seed)")
        _ = generator.next()
    }

    @Test("Whitespace-only queries never return hits", arguments: seeds)
    func whitespace(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let snapshot = SnapshotBuilder()
            .withWidgets([TestSchema.entity("one", name: "Alpha", value: .string("beta"))])
            .build()
        let index = SearchIndex(snapshots: [snapshot])
        for query in ["", " ", "\t", "\n", "  \t\n  "] {
            #expect(index.search(query).isEmpty, "seed \(seed) query \(query.debugDescription)")
        }
        _ = generator.next()
    }
}

@Suite("Redaction invariants")
struct RedactionInvariants {
    private static let seeds: [UInt64] = [6, 12, 18, 24, 30, 36]

    @Test("Redaction never mutates the original snapshot", arguments: seeds)
    func copyOnWrite(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let privacy = generator.pick(PrivacyClassification.allCases)
        let original = SnapshotBuilder()
            .withWidgets(
                [TestSchema.entity("one", name: "Home", value: .string("ssid-\(seed)"))],
                schema: TestSchema.make(privacy: privacy)
            )
            .build()
        let before = original
        for policy in RedactionPolicy.allCases {
            _ = original.redacted(policy)
        }
        #expect(original == before, "seed \(seed)")
    }

    @Test("A stricter policy never reveals a value a looser policy hid", arguments: seeds)
    func monotonicHiding(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let privacy = generator.pick(PrivacyClassification.allCases)
        let snapshot = SnapshotBuilder()
            .withWidgets(
                [TestSchema.entity("one", name: "Home", value: .string("ssid-\(seed)"))],
                schema: TestSchema.make(privacy: privacy)
            )
            .build()
        let none = snapshot.redacted(.none).sections[0].entities[0].properties["value"]
        let standard = snapshot.redacted(.standard).sections[0].entities[0].properties["value"]
        let strict = snapshot.redacted(.strict).sections[0].entities[0].properties["value"]
        if none == .string("‹redacted›") {
            #expect(standard == .string("‹redacted›"), "seed \(seed)")
            #expect(strict == .string("‹redacted›"), "seed \(seed)")
        }
        if standard == .string("‹redacted›") {
            #expect(strict == .string("‹redacted›"), "seed \(seed)")
        }
    }
}

@Suite("Comparator invariants")
struct ComparatorInvariants {
    private static let seeds: [UInt64] = [10, 20, 30, 40, 50, 60]

    @Test("Equality is reflexive for every generated string", arguments: seeds)
    func reflexive(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let value = PropertyValue.string("v-\(generator.next())")
        for rule in [ComparisonRule.exact, .caseInsensitive, .pathNormalized, .semanticVersion, .ignored] {
            #expect(ValueComparator.compare(value, value, rule: rule).areEqual, "seed \(seed) \(rule)")
        }
    }

    @Test("Ignored comparisons are always equal", arguments: seeds)
    func ignoredAlwaysEqual(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let left = PropertyValue.string("a-\(generator.next())")
        let right = PropertyValue.string("b-\(generator.next())")
        #expect(ValueComparator.compare(left, right, rule: .ignored).areEqual, "seed \(seed)")
        #expect(ValueComparator.compare(.absent, right, rule: .ignored).areEqual, "seed \(seed)")
    }

    @Test("Exact inequality is symmetric", arguments: seeds)
    func symmetric(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let left = PropertyValue.string("L\(generator.int(in: 0 ... 20))")
        let right = PropertyValue.string("R\(generator.int(in: 0 ... 20))")
        let forward = ValueComparator.compare(left, right, rule: .exact).areEqual
        let backward = ValueComparator.compare(right, left, rule: .exact).areEqual
        #expect(forward == backward, "seed \(seed)")
    }
}

@Suite("Timeline invariants")
struct TimelineInvariants {
    private static let seeds: [UInt64] = [13, 26, 39, 52, 65, 78]

    @Test("N snapshots produce N-1 steps regardless of input order", arguments: seeds)
    func stepCount(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let count = generator.int(in: 1 ... 8)
        let snapshots = (0 ..< count).map { index in
            SnapshotBuilder(
                id: "t\(index)",
                capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(Double(index) * 60)
            )
            .withWidgets([TestSchema.entity("one", value: .string("v\(index)"))])
            .build()
        }
        let shuffled = generator.shuffled(snapshots)
        let timeline = ChangeTimeline(snapshots: shuffled)
        #expect(timeline.steps.count == max(0, count - 1), "seed \(seed)")
        if count >= 1 {
            #expect(timeline.range != nil, "seed \(seed)")
        }
    }

    @Test("Self-timeline of identical values has zero changes", arguments: seeds)
    func identicalQuiet(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        let value = "same-\(generator.next() % 100)"
        let snapshots = (0 ..< 4).map { index in
            SnapshotBuilder(
                id: "q\(index)",
                capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(Double(index) * 60)
            )
            .withWidgets([TestSchema.entity("one", value: .string(value))])
            .build()
        }
        let timeline = ChangeTimeline(snapshots: snapshots)
        #expect(timeline.totalChanges == 0, "seed \(seed)")
        #expect(timeline.steps.allSatisfy { step in step.diff.isEmpty }, "seed \(seed)")
    }
}
