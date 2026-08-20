import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import DiffuseUI
import Foundation
import SwiftUI
import Testing

/// The UI package is deliberately made of value-driven views, so the parts
/// worth testing are the pure functions that decide what is shown: colour
/// mapping, grouping, and the date headings in the timeline. Rendering itself
/// is exercised by the apps' previews and by the platform builds in CI.
@Suite("Design system")
struct DesignSystemTests {
    @Test("Every severity has a distinct colour")
    func severityColorsAreDistinct() {
        let descriptions = ChangeSeverity.allCases.map { String(describing: $0.color) }
        #expect(Set(descriptions).count == ChangeSeverity.allCases.count)
    }

    @Test("Added and removed read as different colours")
    func changeKindColors() {
        #expect(String(describing: ChangeKind.added.color) != String(describing: ChangeKind.removed.color))
    }

    @Test("Every collection status maps to a colour")
    func statusColors() {
        for status in CollectionStatus.allCases {
            #expect(!String(describing: status.color).isEmpty)
        }
    }

    @Test("Every model type used in a row exposes an SF Symbol name")
    func symbolsArePresent() {
        for severity in ChangeSeverity.allCases {
            #expect(!severity.symbol.isEmpty)
        }
        for kind in ChangeKind.allCases {
            #expect(!kind.symbol.isEmpty)
        }
        for status in CollectionStatus.allCases {
            #expect(!status.symbol.isEmpty)
        }
        for origin in SnapshotOrigin.allCases {
            #expect(!origin.symbol.isEmpty)
        }
        for category in SectionCategory.wellKnown {
            #expect(!category.symbol.isEmpty)
        }
        for privacy in PrivacyClassification.allCases {
            #expect(!privacy.symbol.isEmpty)
        }
    }

    @Test("Ink, paper and accent are distinct colours")
    func paletteIdentity() {
        #expect(String(describing: DiffuseTheme.Palette.ink) != String(describing: DiffuseTheme.Palette.paper))
        #expect(String(describing: DiffuseTheme.Palette.accent) != String(describing: DiffuseTheme.Palette.ink))
        #expect(String(describing: DiffuseTheme.Palette.canvas) != String(describing: DiffuseTheme.Palette.surface))
    }

    @Test("Spacing and radius scales are strictly increasing")
    func metricScales() {
        #expect(DiffuseTheme.Spacing.tight < DiffuseTheme.Spacing.small)
        #expect(DiffuseTheme.Spacing.small < DiffuseTheme.Spacing.regular)
        #expect(DiffuseTheme.Spacing.regular < DiffuseTheme.Spacing.large)
        #expect(DiffuseTheme.Radius.small < DiffuseTheme.Radius.medium)
        #expect(DiffuseTheme.Radius.medium < DiffuseTheme.Radius.large)
    }
}

@Suite("Presentation ordering")
struct PresentationTests {
    private var diff: DiffResult {
        DiffEngine().diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)
    }

    @Test("Changes sort most severe first")
    func changeOrdering() {
        let severities = diff.changes.map(\.severity)
        #expect(severities == severities.sorted(by: >))
    }

    @Test("Sorting is stable across repeated calls")
    func stableOrdering() {
        #expect(diff.changes.map(\.id) == diff.changes.map(\.id))
        #expect(diff.changes.map(\.id) == DiffEngine()
            .diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)
            .changes.map(\.id))
    }

    @Test("Only sections with changes appear in the comparison list")
    func changedSectionsOnly() {
        #expect(diff.changedSections.allSatisfy { !$0.isEmpty })
    }

    @Test("Category grouping covers every change exactly once")
    func categoryGrouping() {
        let grouped = diff.changesByCategory.flatMap(\.changes)
        #expect(grouped.count == diff.changes.count)
        #expect(Set(grouped.map(\.id)) == Set(diff.changes.map(\.id)))
    }

    @Test("Categories present in a diff sort in their declared order")
    func categoryOrdering() {
        let categories = diff.changesByCategory.map(\.category)
        #expect(categories == categories.sorted())
    }

    @Test("Well-known categories sort before unknown ones")
    func unknownCategoriesSortLast() {
        let unknown = SectionCategory("zzz-custom")
        #expect(SectionCategory.system < unknown)
        #expect(SectionCategory.other < unknown)
    }
}

@Suite("Timeline grouping")
struct TimelineGroupingTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("Today and yesterday get friendly headings")
    func relativeHeadings() throws {
        let today = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))

        #expect(SnapshotTimelineView<EmptyView>.title(for: today, calendar: calendar) == "Today")
        #expect(SnapshotTimelineView<EmptyView>.title(for: yesterday, calendar: calendar) == "Yesterday")
    }

    @Test("Older days fall back to a date")
    func absoluteHeadings() throws {
        let old = try #require(calendar.date(byAdding: .day, value: -60, to: Date()))
        let title = SnapshotTimelineView<EmptyView>.title(for: calendar.startOfDay(for: old), calendar: calendar)

        #expect(title != "Today")
        #expect(title != "Yesterday")
        #expect(!title.isEmpty)
    }

    @Test("Summaries carry everything a timeline row needs")
    func summaryContents() {
        let summary = SnapshotSummary(SampleData.macBaseline)

        #expect(summary.displayName == "Morning snapshot")
        #expect(summary.sectionCount == SampleData.macBaseline.sections.count)
        #expect(summary.entityCount == SampleData.macBaseline.entityCount)
        #expect(summary.problemCount == 0)
    }

    @Test("A snapshot with no label falls back to its time")
    func unlabelledSummary() {
        var snapshot = SampleData.macBaseline
        snapshot.label = nil
        #expect(!SnapshotSummary(snapshot).displayName.isEmpty)
    }
}

@Suite("Summary rendering")
struct SummaryRenderingTests {
    @Test("Headlines pluralise correctly")
    func headlines() {
        #expect(DiffSummary.empty.headline == "No changes")

        let one = DiffSummary(
            totalChanges: 1, countsBySeverity: [.notable: 1], countsByKind: [.modified: 1],
            changedSections: 1, comparedSections: 1, asymmetricSections: [], elapsed: 0
        )
        #expect(one.headline == "1 change")

        let many = DiffSummary(
            totalChanges: 17, countsBySeverity: [.notable: 17], countsByKind: [.modified: 17],
            changedSections: 3, comparedSections: 5, asymmetricSections: [], elapsed: 0
        )
        #expect(many.headline == "17 changes")
    }

    @Test("Peak severity is the highest present, or nil when empty")
    func peakSeverity() {
        #expect(DiffSummary.empty.peakSeverity == nil)

        let mixed = DiffSummary(
            totalChanges: 3,
            countsBySeverity: [.informational: 2, .significant: 1],
            countsByKind: [.modified: 3],
            changedSections: 1, comparedSections: 1, asymmetricSections: [], elapsed: 0
        )
        #expect(mixed.peakSeverity == .significant)
    }

    @Test("Cluster headlines describe both count and span")
    func clusterHeadline() {
        let start = SnapshotBuilder.referenceDate
        let cluster = ChangeCluster(
            id: "c",
            start: start,
            end: start.addingTimeInterval(300),
            changeIDs: [ChangeID(rawValue: "a"), ChangeID(rawValue: "b")],
            peakSeverity: .significant,
            capabilities: ["test.widgets"]
        )

        #expect(cluster.headline.contains("2 changes"))
        #expect(cluster.headline.contains("over"))
    }

    @Test("An incomparable section explains itself")
    func incomparableReasons() {
        let missingTarget = SectionDiff(
            capability: "a", displayName: "A", category: .system, symbol: "cpu",
            baseStatus: .collected, targetStatus: nil, changes: [], unchangedEntityCount: 0
        )
        #expect(missingTarget.incomparableReason == "Not collected in the later snapshot")

        let comparable = SectionDiff(
            capability: "a", displayName: "A", category: .system, symbol: "cpu",
            baseStatus: .collected, targetStatus: .collected, changes: [], unchangedEntityCount: 3
        )
        #expect(comparable.incomparableReason == nil)
        #expect(comparable.isComparable)
    }
}

@Suite("Preferences")
struct PreferencePersistenceTests {
    @Test("Cadence and retention round-trip through UserDefaults")
    @MainActor
    func roundTrip() throws {
        let suite = "diffuse.tests.preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = DiffusePreferences(defaults: defaults)
        first.cadence = .hourly
        first.retentionDays = 30
        first.redaction = .strict
        first.skipsWhenUnchanged = false
        first.capturesOnSystemEvents = false

        let second = DiffusePreferences(defaults: defaults)
        #expect(second.cadence == .hourly)
        #expect(second.retentionDays == 30)
        #expect(second.redaction == .strict)
        #expect(second.skipsWhenUnchanged == false)
        #expect(second.capturesOnSystemEvents == false)
        #expect(second.schedule.cadence == .hourly)
        #expect(second.retentionPolicy.age == .days(30))
    }
}
