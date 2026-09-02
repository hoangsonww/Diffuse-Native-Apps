import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

/// The layer between the diff engine and every surface that shows a diff.
///
/// `ComparatorAndModelTests` proves values compare correctly; this proves the
/// results are *presented* correctly — deterministic ordering, aggregate
/// counts, cluster headlines, and the one-line explanations the UI shows when a
/// section could not be compared. These derived properties have no other
/// coverage, and the Mac, iPad, iPhone and Watch apps all read them.
@Suite("Diff presentation")
struct DiffPresentationTests {
    // MARK: - Property changes

    @Test("A numeric delta is signed and only defined when both sides are numeric")
    func numericDelta() {
        #expect(change(before: .integer(10), after: .integer(25)).delta == 15)
        #expect(change(before: .integer(25), after: .integer(10)).delta == -15)
        #expect(change(before: .bytes(1000), after: .bytes(1500)).delta == 500)
        #expect(change(before: .string("a"), after: .string("b")).delta == nil)
        #expect(change(before: .integer(1), after: .absent).delta == nil)
    }

    @Test("Direction follows the numeric delta, and equal values are lateral")
    func numericDirection() {
        #expect(change(before: .integer(1), after: .integer(2)).direction == .increased)
        #expect(change(before: .integer(2), after: .integer(1)).direction == .decreased)
        #expect(change(before: .integer(2), after: .integer(2)).direction == .lateral)
        #expect(change(before: .string("a"), after: .string("b")).direction == .lateral,
                "text has no order, so it can only be lateral")
    }

    /// Versions must not be compared as numbers: `1.9.0 → 1.10.0` is an
    /// increase, but any numeric reading of those strings says otherwise.
    @Test("Version direction uses semantic ordering, not string or numeric order")
    func versionDirection() throws {
        let older = try #require(SemanticVersion("1.9.0"))
        let newer = try #require(SemanticVersion("1.10.0"))
        #expect(change(before: .version(older), after: .version(newer)).direction == .increased)
        #expect(change(before: .version(newer), after: .version(older)).direction == .decreased)
        #expect(change(before: .version(newer), after: .version(newer)).direction == .lateral)
    }

    @Test("Every direction has a distinct symbol")
    func directionSymbols() {
        let symbols = [
            PropertyChange.Direction.increased,
            .decreased,
            .lateral,
        ].map(\.symbol)
        #expect(Set(symbols).count == 3)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test("A formatted property change reads before → after")
    func formattedChange() {
        let formatted = change(before: .integer(1), after: .integer(2)).formatted()
        #expect(formatted.contains("→"))
        #expect(formatted.hasPrefix("1"))
        #expect(formatted.hasSuffix("2"))
    }

    // MARK: - Change identity

    /// Change ids are derived from what changed, not generated, so two runs of
    /// the engine over the same snapshots produce byte-identical output. Golden
    /// fixtures depend on this.
    @Test("Change ids are deterministic and distinguish property from entity changes")
    func changeIDsAreDerived() {
        let identity = EntityIdentity(kind: TestSchema.widget, value: "one")
        let modified = ChangeID(
            capability: TestSchema.capability,
            identity: identity,
            property: "value",
            kind: .modified
        )
        let repeated = ChangeID(
            capability: TestSchema.capability,
            identity: identity,
            property: "value",
            kind: .modified
        )
        let added = ChangeID(capability: TestSchema.capability, identity: identity, property: nil, kind: .added)

        #expect(modified == repeated, "the same change twice must produce the same id")
        #expect(modified != added)
        #expect(modified.rawValue.contains("value"))
        #expect(!added.rawValue.contains("value"), "a whole-entity change carries no property segment")
        #expect(modified.description == modified.rawValue)
    }

    @Test("Change ids sort by raw value")
    func changeIDOrdering() {
        #expect(ChangeID(rawValue: "a") < ChangeID(rawValue: "b"))
        #expect(!(ChangeID(rawValue: "b") < ChangeID(rawValue: "a")))
    }

    // MARK: - Change presentation

    @Test("A breadcrumb joins the section and the entity")
    func breadcrumb() {
        let sample = makeChange(id: "one", summary: "Widget changed")
        #expect(sample.breadcrumb == "Widgets › Widget one")
    }

    /// Search has to match on things the user can actually see, and matching is
    /// case-insensitive, so the haystack is lowercased once here rather than at
    /// every call site.
    @Test("Search text is lowercased and spans every visible field")
    func searchText() {
        let sample = makeChange(id: "one", summary: "Node Upgraded")
        #expect(sample.searchText == sample.searchText.lowercased())
        #expect(sample.searchText.contains("node upgraded"))
        #expect(sample.searchText.contains("widgets"))
        #expect(sample.searchText.contains(TestSchema.capability.rawValue))
    }

    @Test("Presentation order puts the most severe change first")
    func presentationOrderBySeverity() {
        let ordered = [
            makeChange(id: "a", severity: .informational),
            makeChange(id: "b", severity: .critical),
            makeChange(id: "c", severity: .notable),
        ].sortedForPresentation()

        #expect(ordered.map(\.severity) == [.critical, .notable, .informational])
    }

    @Test("Presentation order is stable for equally severe changes")
    func presentationOrderIsStable() {
        let changes = [
            makeChange(id: "c", severity: .notable),
            makeChange(id: "a", severity: .notable),
            makeChange(id: "b", severity: .notable),
        ]
        let once = changes.sortedForPresentation().map(\.id)
        let twice = changes.shuffled().sortedForPresentation().map(\.id)
        #expect(once == twice, "sorting must not depend on input order")
    }

    @Test("Filtering by minimum severity is inclusive of the threshold")
    func severityFilter() {
        let changes = ChangeSeverity.allCases.map { makeChange(id: $0.rawValue, severity: $0) }
        #expect(changes.filtered(minimumSeverity: .informational).count == ChangeSeverity.allCases.count)
        #expect(changes.filtered(minimumSeverity: .critical).map(\.severity) == [.critical])
        #expect(changes.filtered(minimumSeverity: .significant).allSatisfy { $0.severity >= .significant })
    }

    // MARK: - Diff summary

    @Test("A summary counts by severity and by kind, defaulting missing keys to zero")
    func summaryCounts() {
        let summary = DiffSummary(
            totalChanges: 3,
            countsBySeverity: [.critical: 1, .notable: 2],
            countsByKind: [.added: 3],
            changedSections: 1,
            comparedSections: 4,
            asymmetricSections: [],
            elapsed: 60
        )

        #expect(summary.count(.critical) == 1)
        #expect(summary.count(.informational) == 0, "an absent severity reads as zero, not nil")
        #expect(summary.count(ChangeKind.added) == 3)
        #expect(summary.count(ChangeKind.removed) == 0)
        #expect(!summary.isEmpty)
    }

    @Test("Significant counts fold critical in with significant")
    func significantCount() {
        let summary = DiffSummary(
            totalChanges: 6,
            countsBySeverity: [.informational: 1, .notable: 2, .significant: 2, .critical: 1],
            countsByKind: [:],
            changedSections: 1,
            comparedSections: 1,
            asymmetricSections: [],
            elapsed: 0
        )
        #expect(summary.significantCount == 3, "2 significant + 1 critical")
    }

    @Test("Peak severity is the most severe present, and nil for an empty diff")
    func peakSeverity() {
        #expect(DiffSummary.empty.peakSeverity == nil)
        #expect(DiffSummary.empty.isEmpty)

        let summary = DiffSummary(
            totalChanges: 2,
            countsBySeverity: [.informational: 1, .significant: 1],
            countsByKind: [:],
            changedSections: 1,
            comparedSections: 1,
            asymmetricSections: [],
            elapsed: 0
        )
        #expect(summary.peakSeverity == .significant)
    }

    /// Severities recorded with a zero count must not be mistaken for present.
    @Test("A zero count does not register as the peak severity")
    func peakSeverityIgnoresZeroCounts() {
        let summary = DiffSummary(
            totalChanges: 1,
            countsBySeverity: [.critical: 0, .notable: 1],
            countsByKind: [:],
            changedSections: 1,
            comparedSections: 1,
            asymmetricSections: [],
            elapsed: 0
        )
        #expect(summary.peakSeverity == .notable)
    }

    @Test("The headline pluralises correctly at zero, one and many")
    func summaryHeadline() {
        #expect(DiffSummary.empty.headline == "No changes")
        #expect(summary(total: 1).headline == "1 change")
        #expect(summary(total: 17).headline == "17 changes")
    }

    // MARK: - Section diffs

    @Test("A section with data on both sides is comparable and has no excuse to show")
    func comparableSection() {
        let section = makeSection(base: .collected, target: .collected, changes: [makeChange(id: "one")])
        #expect(section.isComparable)
        #expect(section.incomparableReason == nil)
        #expect(!section.isEmpty)
        #expect(section.peakSeverity == .notable)
        #expect(section.id == TestSchema.capability)
    }

    @Test("An empty section reports no peak severity")
    func emptySection() {
        let section = makeSection(base: .collected, target: .collected, changes: [])
        #expect(section.isEmpty)
        #expect(section.peakSeverity == nil)
    }

    /// A missing side means "we could not look", which is a different message
    /// from "nothing changed" — conflating the two is how a diff quietly lies.
    @Test("Each incomparable combination explains itself in one line")
    func incomparableReasons() {
        let firstSeen = makeSection(base: nil, target: .collected, changes: [])
        #expect(firstSeen.incomparableReason == "First seen in the later snapshot")

        let vanished = makeSection(base: .collected, target: nil, changes: [])
        #expect(vanished.incomparableReason == "Not collected in the later snapshot")

        let neverCollected = makeSection(base: nil, target: nil, changes: [])
        #expect(neverCollected.incomparableReason != nil)

        let failedLater = makeSection(base: .collected, target: .unavailable, changes: [])
        let laterReason = failedLater.incomparableReason
        #expect(laterReason?.contains("later snapshot") == true)

        let failedEarlier = makeSection(base: .unavailable, target: .collected, changes: [])
        #expect(failedEarlier.incomparableReason?.contains("earlier snapshot") == true)

        let failedBoth = makeSection(base: .unavailable, target: .unavailable, changes: [])
        #expect(failedBoth.incomparableReason?.contains("either snapshot") == true)

        for section in [firstSeen, vanished, neverCollected, failedLater, failedEarlier, failedBoth] {
            #expect(!section.isComparable)
        }
    }

    // MARK: - Clusters

    @Test("A cluster reports its span, count and a readable headline")
    func clusterHeadline() {
        let start = Date(timeIntervalSince1970: 1000)
        let single = ChangeCluster(
            id: "a",
            start: start,
            end: start,
            changeIDs: [ChangeID(rawValue: "one")],
            peakSeverity: .notable,
            capabilities: [TestSchema.capability]
        )
        #expect(single.count == 1)
        #expect(single.duration == 0)
        #expect(single.headline == "1 change", "an instantaneous cluster names no span")

        let spread = ChangeCluster(
            id: "b",
            start: start,
            end: start.addingTimeInterval(300),
            changeIDs: [ChangeID(rawValue: "one"), ChangeID(rawValue: "two")],
            peakSeverity: .critical,
            capabilities: [TestSchema.capability]
        )
        #expect(spread.count == 2)
        #expect(spread.duration == 300)
        #expect(spread.headline.hasPrefix("2 changes over "))
    }

    // MARK: - Diff results

    @Test("A diff result flattens every section into one ordered change list")
    func resultChanges() {
        let result = makeResult(sections: [
            makeSection(changes: [makeChange(id: "quiet", severity: .informational)]),
            makeSection(capability: "test.other", changes: [makeChange(id: "loud", severity: .critical)]),
        ])

        #expect(result.changes.count == 2)
        #expect(result.changes.first?.severity == .critical, "the flattened list is in presentation order")
        #expect(result.id.contains(".."), "the id names both snapshots")
    }

    @Test("A change can be looked up by id, and an unknown id returns nil")
    func lookupByID() {
        let wanted = makeChange(id: "wanted")
        let result = makeResult(sections: [makeSection(changes: [wanted, makeChange(id: "other")])])

        #expect(result.change(id: wanted.id)?.id == wanted.id)
        #expect(result.change(id: ChangeID(rawValue: "absent")) == nil)
    }

    @Test("Cluster membership resolves to the changes it names, ignoring unknown ids")
    func clusterMembership() {
        let first = makeChange(id: "first")
        let second = makeChange(id: "second")
        let result = makeResult(sections: [makeSection(changes: [first, second])])

        let cluster = ChangeCluster(
            id: "c",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1),
            changeIDs: [first.id, ChangeID(rawValue: "ghost")],
            peakSeverity: .notable,
            capabilities: [TestSchema.capability]
        )

        let resolved = result.changes(in: cluster)
        #expect(resolved.map(\.id) == [first.id], "a stale id must not fabricate a change")
    }

    @Test("Only sections with changes appear in the changed list, most severe first")
    func changedSectionsOrdering() {
        let result = makeResult(sections: [
            makeSection(capability: "test.empty", changes: []),
            makeSection(capability: "test.quiet", changes: [makeChange(id: "a", severity: .informational)]),
            makeSection(capability: "test.loud", changes: [makeChange(id: "b", severity: .critical)]),
        ])

        let changed = result.changedSections
        #expect(changed.count == 2, "the empty section is dropped")
        #expect(changed.first?.peakSeverity == .critical)
    }

    @Test("Filtering a result by severity applies to the flattened list")
    func resultSeverityFilter() {
        let result = makeResult(sections: [
            makeSection(changes: [
                makeChange(id: "a", severity: .informational),
                makeChange(id: "b", severity: .critical),
            ]),
        ])

        #expect(result.changes(minimumSeverity: .significant).map(\.severity) == [.critical])
        #expect(result.changes(minimumSeverity: .informational).count == 2)
    }

    @Test("Grouping by category is ordered and loses nothing")
    func changesByCategory() {
        let result = makeResult(sections: [
            makeSection(
                capability: "test.hardware",
                category: .hardware,
                changes: [makeChange(id: "h", category: .hardware)]
            ),
            makeSection(
                capability: "test.system",
                category: .system,
                changes: [makeChange(id: "s", category: .system)]
            ),
        ])

        let grouped = result.changesByCategory
        #expect(grouped.map(\.category) == [.system, .hardware], "well-known categories keep their declared order")
        #expect(grouped.flatMap(\.changes).count == result.changes.count, "grouping must not drop a change")
    }

    @Test("An empty diff is empty at every level")
    func emptyResult() {
        let result = makeResult(sections: [])
        #expect(result.isEmpty)
        #expect(result.changes.isEmpty)
        #expect(result.changedSections.isEmpty)
        #expect(result.changesByCategory.isEmpty)
    }

    // MARK: - Fixtures

    private func change(before: PropertyValue, after: PropertyValue) -> PropertyChange {
        PropertyChange(key: "value", displayName: "Value", before: before, after: after)
    }

    private func summary(total: Int) -> DiffSummary {
        DiffSummary(
            totalChanges: total,
            countsBySeverity: [:],
            countsByKind: [:],
            changedSections: 1,
            comparedSections: 1,
            asymmetricSections: [],
            elapsed: 0
        )
    }

    private func makeChange(
        id: String,
        severity: ChangeSeverity = .notable,
        category: SectionCategory = .system,
        summary: String = "Widget changed"
    ) -> Change {
        let identity = EntityIdentity(kind: TestSchema.widget, value: id)
        return Change(
            id: ChangeID(capability: TestSchema.capability, identity: identity, property: "value", kind: .modified),
            kind: .modified,
            capability: TestSchema.capability,
            sectionName: "Widgets",
            category: category,
            entity: EntityReference(identity: identity, displayName: "Widget \(id)", symbol: "square"),
            property: change(before: .integer(1), after: .integer(2)),
            severity: severity,
            observedAt: Date(timeIntervalSince1970: 1000),
            summary: summary
        )
    }

    private func makeSection(
        capability: CapabilityID = TestSchema.capability,
        category: SectionCategory = .system,
        base: CollectionStatus? = .collected,
        target: CollectionStatus? = .collected,
        changes: [Change]
    ) -> SectionDiff {
        SectionDiff(
            capability: capability,
            displayName: "Widgets",
            category: category,
            symbol: "square",
            baseStatus: base,
            targetStatus: target,
            changes: changes,
            unchangedEntityCount: 0
        )
    }

    private func makeResult(sections: [SectionDiff]) -> DiffResult {
        let changes = sections.flatMap(\.changes)
        return DiffResult(
            base: reference(id: "base", offset: 0),
            target: reference(id: "target", offset: 3600),
            generatedAt: Date(timeIntervalSince1970: 3600),
            summary: DiffSummary(
                totalChanges: changes.count,
                countsBySeverity: Dictionary(grouping: changes, by: \.severity).mapValues(\.count),
                countsByKind: Dictionary(grouping: changes, by: \.kind).mapValues(\.count),
                changedSections: sections.count(where: { !$0.isEmpty }),
                comparedSections: sections.count,
                asymmetricSections: [],
                elapsed: 3600
            ),
            sectionDiffs: sections,
            clusters: []
        )
    }

    private func reference(id: String, offset: TimeInterval) -> SnapshotReference {
        SnapshotReference(
            id: SnapshotID(rawValue: id),
            capturedAt: Date(timeIntervalSince1970: offset),
            label: nil,
            platform: .current,
            deviceName: "Test Device",
            origin: .manual
        )
    }
}
