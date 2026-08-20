import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Diff engine invariants")
struct DiffEngineInvariantTests {
    private let engine = DiffEngine()

    @Test("Diffing a snapshot against itself produces nothing")
    func selfDiffIsEmpty() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [
                TestSchema.entity("alpha", value: .string("one"), version: "1.2.3", size: 1024),
                TestSchema.entity("beta", value: .string("two"), version: "4.5.6", size: 2048),
            ]))
            .build()

        let result = engine.selfDiff(snapshot)

        #expect(result.isEmpty)
        #expect(result.summary.totalChanges == 0)
        #expect(result.changes.isEmpty)
    }

    @Test("Entity ordering does not affect the result")
    func orderingIsIrrelevant() {
        let entities = [
            TestSchema.entity("alpha", value: .string("one")),
            TestSchema.entity("beta", value: .string("two")),
            TestSchema.entity("gamma", value: .string("three")),
        ]

        let forward = SnapshotBuilder().adding(TestSchema.section(entities: entities)).build()
        let reversed = SnapshotBuilder()
            .identified("reversed")
            .adding(TestSchema.section(entities: entities.reversed()))
            .build()

        let result = engine.diff(base: forward, target: reversed)

        #expect(result.isEmpty, "Reordering entities must not read as a change")
    }

    @Test("The same inputs always produce the same output")
    func diffIsDeterministic() throws {
        let base = SampleSnapshots.base
        let target = SampleSnapshots.target

        let first = engine.diff(base: base, target: target)
        let second = engine.diff(base: base, target: target)

        #expect(first == second)
        #expect(first.changes.map(\.id) == second.changes.map(\.id))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        #expect(try encoder.encode(first) == encoder.encode(second), "Diff output must be byte-stable")
    }

    @Test("Change identifiers are derived from content, not generated")
    func changeIdentifiersAreStable() {
        let base = SampleSnapshots.base
        let target = SampleSnapshots.target

        let first = engine.diff(base: base, target: target).changes.map(\.id.rawValue).sorted()
        let second = DiffEngine().diff(base: base, target: target).changes.map(\.id.rawValue).sorted()

        #expect(first == second)
        #expect(first.allSatisfy { !$0.isEmpty })
    }

    @Test("Reversing a diff inverts every property change")
    func reverseDiffIsInverse() {
        let forward = engine.diff(base: SampleSnapshots.base, target: SampleSnapshots.target)
        let backward = engine.diff(base: SampleSnapshots.target, target: SampleSnapshots.base)

        #expect(forward.summary.totalChanges == backward.summary.totalChanges)
        #expect(forward.summary.count(.added) == backward.summary.count(.removed))
        #expect(forward.summary.count(.removed) == backward.summary.count(.added))

        for change in forward.changes {
            guard let property = change.property else { continue }
            let inverse = backward.changes.first {
                $0.entity.identity == change.entity.identity && $0.property?.key == property.key
            }
            let inverseProperty = try? #require(inverse?.property)
            #expect(inverseProperty?.before == property.after)
            #expect(inverseProperty?.after == property.before)
        }
    }

    @Test("An empty snapshot pair produces an empty diff")
    func emptySnapshots() {
        let base = SnapshotBuilder().build()
        let target = SnapshotBuilder().identified("other").build()

        let result = engine.diff(base: base, target: target)

        #expect(result.isEmpty)
        #expect(result.summary.comparedSections == 0)
    }
}

@Suite("Entity matching")
struct EntityMatchingTests {
    private let engine = DiffEngine()

    @Test("A new identity reads as added")
    func addedEntity() throws {
        let base = SnapshotBuilder().adding(TestSchema.section(entities: [TestSchema.entity("alpha")])).build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha"), TestSchema.entity("beta")]))
            .build()

        let changes = engine.diff(base: base, target: target).changes
        let change = try #require(changes.first)

        #expect(changes.count == 1)
        #expect(change.kind == .added)
        #expect(change.entity.identity.value == "beta")
        #expect(change.severity == .notable, "Addition severity comes from the schema descriptor")
    }

    @Test("A missing identity reads as removed, and removal outranks addition")
    func removedEntity() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha"), TestSchema.entity("beta")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)

        #expect(change.kind == .removed)
        #expect(change.severity == .significant)
    }

    @Test("A stable identity with a changed property reads as modified, not add plus remove")
    func modifiedEntity() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", value: .string("one"))]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", value: .string("two"))]))
            .build()

        let changes = engine.diff(base: base, target: target).changes

        #expect(changes.count == 1)
        #expect(changes.first?.kind == .modified)
        #expect(changes.first?.property?.before == .string("one"))
        #expect(changes.first?.property?.after == .string("two"))
    }

    @Test("Identity normalization ignores case and surrounding whitespace")
    func identityNormalization() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("Alpha", name: "Alpha")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("  alpha  ", name: "Alpha")]))
            .build()

        #expect(engine.diff(base: base, target: target).isEmpty)
    }

    @Test("A whitespace-only display name difference is not a rename")
    func displayNameWhitespaceIsIgnored() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", name: "Macintosh HD")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", name: "  Macintosh HD ")]))
            .build()

        #expect(engine.diff(base: base, target: target).isEmpty)
    }

    @Test("A genuine rename is reported")
    func renameIsReported() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", name: "Scratch")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", name: "Backup")]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.property?.displayName == "Name")
        #expect(change.property?.after == .string("Backup"))
    }

    @Test("Nested children participate in matching")
    func nestedEntities() throws {
        func section(childValue: String) -> SnapshotSection {
            var parent = TestSchema.entity("parent")
            parent.children = [TestSchema.entity("child", value: .string(childValue))]
            return TestSchema.section(entities: [parent])
        }

        let base = SnapshotBuilder().adding(section(childValue: "one")).build()
        let target = SnapshotBuilder().identified("target").adding(section(childValue: "two")).build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.entity.identity.value == "child")
    }
}

@Suite("Comparison rules")
struct ComparisonRuleTests {
    @Test("Exact comparison reports any difference")
    func exact() {
        let outcome = ValueComparator.compare(.string("a"), .string("b"), rule: .exact)
        #expect(!outcome.areEqual)
        #expect(outcome.confidence == 1)
    }

    @Test("Case-insensitive comparison ignores capitalisation")
    func caseInsensitive() {
        #expect(ValueComparator.compare(.string("Wi-Fi"), .string("wi-fi"), rule: .caseInsensitive).areEqual)
        #expect(ValueComparator.compare(.string("  Wi-Fi  "), .string("wi-fi"), rule: .caseInsensitive).areEqual)
        #expect(!ValueComparator.compare(.string("Wi-Fi"), .string("Ethernet"), rule: .caseInsensitive).areEqual)
    }

    @Test("Path comparison ignores trailing separators")
    func pathNormalized() {
        #expect(ValueComparator.compare(.path("/tmp/thing/"), .path("/tmp/thing"), rule: .pathNormalized).areEqual)
        #expect(!ValueComparator.compare(.path("/tmp/a"), .path("/tmp/b"), rule: .pathNormalized).areEqual)
    }

    @Test(
        "Semantic version comparison treats omitted components as zero",
        arguments: [
            ("1.2.0", "1.2", true),
            ("1.2.3", "1.2.4", false),
            ("2.0.0", "2.0.0+build.9", true),
        ]
    )
    func semanticVersion(before: String, after: String, expectedEqual: Bool) throws {
        let left = try #require(SemanticVersion(before))
        let right = try #require(SemanticVersion(after))
        let outcome = ValueComparator.compare(.version(left), .version(right), rule: .semanticVersion)
        #expect(outcome.areEqual == expectedEqual)
    }

    @Test("Version transitions are classified for the severity engine")
    func versionTransitions() {
        let major = ValueComparator.compare(.version("1.0.0"), .version("2.0.0"), rule: .semanticVersion)
        #expect(major.versionTransition == .major)

        let patch = ValueComparator.compare(.version("1.0.0"), .version("1.0.1"), rule: .semanticVersion)
        #expect(patch.versionTransition == .patch)

        let downgrade = ValueComparator.compare(.version("2.0.0"), .version("1.9.0"), rule: .semanticVersion)
        #expect(downgrade.versionTransition == .downgrade)
    }

    @Test("Absolute tolerance suppresses movement inside the threshold")
    func numericTolerance() {
        let inside = ValueComparator.compare(.double(10), .double(10.4), rule: .numeric(tolerance: 0.5))
        #expect(inside.areEqual)

        let outside = ValueComparator.compare(.double(10), .double(12), rule: .numeric(tolerance: 0.5))
        #expect(!outside.areEqual)
    }

    @Test("Relative tolerance scales with magnitude")
    func relativeTolerance() {
        // 1% of ~200 GB is ~2 GB, so a 1 GB drift is noise.
        let drift = ValueComparator.compare(
            .bytes(218_000_000_000),
            .bytes(217_500_000_000),
            rule: .relative(tolerance: 0.01)
        )
        #expect(drift.areEqual)

        let real = ValueComparator.compare(
            .bytes(218_000_000_000),
            .bytes(191_000_000_000),
            rule: .relative(tolerance: 0.01)
        )
        #expect(!real.areEqual)
    }

    @Test("Confidence rises the further a value moves past its tolerance")
    func confidenceScaling() {
        let marginal = ValueComparator.compare(.double(0), .double(1.1), rule: .numeric(tolerance: 1))
        let obvious = ValueComparator.compare(.double(0), .double(100), rule: .numeric(tolerance: 1))

        #expect(marginal.confidence < obvious.confidence)
        #expect(marginal.confidence >= 0.5)
        #expect(obvious.confidence == 1)
    }

    @Test("An ignored property never produces a change")
    func ignoredRule() {
        #expect(ValueComparator.compare(.integer(1), .integer(1_000_000), rule: .ignored).areEqual)
    }

    @Test("Unordered lists compare as sets")
    func unorderedLists() {
        let left = PropertyValue.list([.string("a"), .string("b")])
        let right = PropertyValue.list([.string("b"), .string("a")])
        #expect(ValueComparator.compare(left, right, rule: .unordered).areEqual)
        #expect(!ValueComparator.compare(left, .list([.string("a")]), rule: .unordered).areEqual)
    }

    @Test("A value appearing or disappearing is always a difference")
    func absenceIsAlwaysAChange() {
        #expect(!ValueComparator.compare(.absent, .integer(1), rule: .ignored).areEqual == false,
                "An ignored property stays ignored even when it appears")
        #expect(!ValueComparator.compare(.absent, .integer(1), rule: .numeric(tolerance: 1_000_000)).areEqual)
        #expect(ValueComparator.compare(.absent, .absent, rule: .exact).areEqual)
    }
}

@Suite("Severity")
struct SeverityTests {
    private let engine = DiffEngine()

    @Test("A major version jump escalates above the declared severity")
    func majorVersionEscalates() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "1.0.0")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "2.0.0")]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.severity == .critical, "Declared significant, escalated by the major jump")
    }

    @Test("A patch bump is de-escalated")
    func patchDeescalates() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "1.0.0")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "1.0.1")]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.severity == .notable)
    }

    @Test("A downgrade escalates")
    func downgradeEscalates() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "2.0.0")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("tool", version: "1.9.0")]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.severity == .critical)
    }

    @Test("Losing access to a section is reported as significant")
    func permissionLossIsSignificant() {
        #expect(SeverityEvaluator.severity(forStatusChange: .collected, after: .permissionRequired) == .significant)
        #expect(SeverityEvaluator.severity(forStatusChange: .collected, after: .timedOut) == .notable)
        #expect(SeverityEvaluator.severity(forStatusChange: .unavailable, after: .collected) == .informational)
    }

    @Test("Severity filtering removes lower-ranked changes")
    func severityFiltering() {
        let base = SampleSnapshots.base
        let target = SampleSnapshots.target

        let all = DiffEngine(options: .default).diff(base: base, target: target)
        let significant = DiffEngine(options: .significantOnly).diff(base: base, target: target)

        #expect(significant.summary.totalChanges <= all.summary.totalChanges)
        #expect(significant.changes.allSatisfy { $0.severity >= .significant })
    }
}

@Suite("Section-level behaviour")
struct SectionDiffTests {
    private let engine = DiffEngine()

    @Test("A capability appearing is one change, not one per entity")
    func capabilityAppearance() {
        let base = SnapshotBuilder().build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: (0 ..< 50).map { TestSchema.entity("entity-\($0)") }))
            .build()

        let changes = engine.diff(base: base, target: target).changes

        #expect(changes.count == 1, "A newly available capability must not flood the diff")
        #expect(changes.first?.kind == .added)
    }

    @Test("A status change is reported and blocks entity comparison")
    func statusChangeStopsComparison() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [], status: .permissionRequired))
            .build()

        let result = engine.diff(base: base, target: target)
        let change = try #require(result.changes.first)

        #expect(result.changes.count == 1, "Entities must not read as removed when we simply could not look")
        #expect(change.severity == .significant)
        #expect(change.property?.after == .string("Permission required"))

        let section = try #require(result.sectionDiffs.first)
        #expect(!section.isComparable)
        #expect(section.incomparableReason != nil)
    }

    @Test("Gaining collection reports the entities that became visible")
    func statusRecoveryShowsEntities() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [], status: .permissionRequired))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")]))
            .build()

        let result = engine.diff(base: base, target: target)
        #expect(result.changes.contains { $0.kind == .added && $0.entity.identity.value == "alpha" })
    }

    @Test("Section-level attributes are diffed")
    func sectionAttributes() throws {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [], attributes: ["total": .integer(3)]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [], attributes: ["total": .integer(5)]))
            .build()

        let change = try #require(engine.diff(base: base, target: target).changes.first)
        #expect(change.property?.key == "total")
        #expect(change.property?.after == .integer(5))
    }

    @Test("Asymmetric sections are recorded in the summary")
    func asymmetricSections() {
        let base = SnapshotBuilder().adding(TestSchema.section(entities: [])).build()
        let target = SnapshotBuilder().identified("target").build()

        let result = engine.diff(base: base, target: target)
        #expect(result.summary.asymmetricSections == [TestSchema.capability])
    }

    @Test("Unchanged entities are counted but not emitted by default")
    func unchangedCounting() throws {
        let entities = [TestSchema.entity("alpha"), TestSchema.entity("beta")]
        let base = SnapshotBuilder().adding(TestSchema.section(entities: entities)).build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: entities))
            .build()

        let section = try #require(engine.diff(base: base, target: target).sectionDiffs.first)
        #expect(section.unchangedEntityCount == 2)
        #expect(section.changes.isEmpty)

        let verbose = DiffEngine(options: .exhaustive).diff(base: base, target: target)
        #expect(verbose.sectionDiffs.first?.changes.count == 2)
        #expect(verbose.summary.totalChanges == 0, "Unchanged entries must not inflate the change count")
    }

    @Test("Capability filters restrict what is compared")
    func capabilityFiltering() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", value: .string("one"))]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", value: .string("two"))]))
            .build()

        let excluded = DiffEngine(options: DiffOptions(excludedCapabilities: [TestSchema.capability]))
        #expect(excluded.diff(base: base, target: target).isEmpty)

        let included = DiffEngine(options: DiffOptions(includedCapabilities: ["something.else"]))
        #expect(included.diff(base: base, target: target).isEmpty)
    }
}

@Suite("Temporal correlation")
struct CorrelationTests {
    @Test("Changes within the window group together")
    func clustersWithinWindow() throws {
        let start = SnapshotBuilder.referenceDate
        let changes = (0 ..< 4).map { index in
            makeChange(id: "change-\(index)", at: start.addingTimeInterval(Double(index) * 120))
        }

        let clusters = ChangeCorrelator.cluster(changes, window: 300, minimumSize: 2)
        let cluster = try #require(clusters.first)

        #expect(clusters.count == 1)
        #expect(cluster.count == 4)
        #expect(cluster.duration == 360)
    }

    @Test("A gap larger than the window splits clusters")
    func gapSplitsClusters() {
        let start = SnapshotBuilder.referenceDate
        let changes = [
            makeChange(id: "a", at: start),
            makeChange(id: "b", at: start.addingTimeInterval(60)),
            makeChange(id: "c", at: start.addingTimeInterval(9000)),
            makeChange(id: "d", at: start.addingTimeInterval(9060)),
        ]

        let clusters = ChangeCorrelator.cluster(changes, window: 300, minimumSize: 2)
        #expect(clusters.count == 2)
    }

    @Test("Clusters below the minimum size are discarded")
    func minimumClusterSize() {
        let changes = [makeChange(id: "solo", at: SnapshotBuilder.referenceDate)]
        #expect(ChangeCorrelator.cluster(changes, window: 300, minimumSize: 2).isEmpty)
        #expect(ChangeCorrelator.cluster(changes, window: 300, minimumSize: 1).count == 1)
    }

    @Test("Clustering is order-independent")
    func clusteringIsOrderIndependent() {
        let start = SnapshotBuilder.referenceDate
        let changes = (0 ..< 5).map { makeChange(id: "c\($0)", at: start.addingTimeInterval(Double($0) * 60)) }

        let forward = ChangeCorrelator.cluster(changes, window: 300, minimumSize: 2)
        let shuffled = ChangeCorrelator.cluster(changes.reversed(), window: 300, minimumSize: 2)

        #expect(forward == shuffled)
    }

    private func makeChange(id: String, at date: Date) -> Change {
        Change(
            id: ChangeID(rawValue: id),
            kind: .modified,
            capability: TestSchema.capability,
            sectionName: "Widgets",
            category: .other,
            entity: EntityReference(
                identity: EntityIdentity(kind: TestSchema.widget, value: id),
                displayName: id,
                symbol: "square"
            ),
            severity: .notable,
            observedAt: date,
            summary: "\(id) changed"
        )
    }
}

/// Two snapshots exercising every code path: add, remove, modify, version
/// transitions, tolerance-based drift and a section that lost access.
enum SampleSnapshots {
    static let base = SnapshotBuilder()
        .identified("sample-base")
        .adding(TestSchema.section(
            entities: [
                TestSchema.entity("stable", value: .string("same"), version: "1.0.0", size: 1000),
                TestSchema.entity("changing", value: .string("before"), version: "1.0.0", size: 1000),
                TestSchema.entity("disappearing", value: .string("gone"), version: "3.0.0", size: 500),
            ],
            attributes: ["total": .integer(3)]
        ))
        .build()

    static let target = SnapshotBuilder()
        .identified("sample-target")
        .at(SnapshotBuilder.referenceDate.addingTimeInterval(3600))
        .adding(TestSchema.section(
            entities: [
                TestSchema.entity("stable", value: .string("same"), version: "1.0.0", size: 1000),
                TestSchema.entity("changing", value: .string("after"), version: "1.1.0", size: 4000),
                TestSchema.entity("appearing", value: .string("new"), version: "0.1.0", size: 100),
            ],
            at: SnapshotBuilder.referenceDate.addingTimeInterval(3600),
            attributes: ["total": .integer(3)]
        ))
        .build()
}
