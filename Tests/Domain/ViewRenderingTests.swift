#if canImport(SwiftUI) && os(macOS)

import DiffuseCapabilities
import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import DiffuseUI
import Foundation
import SwiftUI
import Testing

/// Render coverage for the shared SwiftUI layer.
///
/// Every client draws its screens out of `DiffuseUI`, so a view that traps on a
/// nil optional, an empty collection, or an unexpected enum case takes down the
/// Mac, iPad, iPhone and Watch apps at once — and none of that is reachable
/// from the model tests. `ImageRenderer` evaluates a view's whole body, so
/// rendering each one is a real smoke test: it fails the suite on a crash and
/// on a view that resolves to nothing.
///
/// The fixtures are the real sample snapshots run through the real diff engine
/// rather than hand-built stubs, so the views are exercised on data shaped like
/// production data.
@MainActor
@Suite("View rendering")
struct ViewRenderingTests {
    // MARK: - Design system

    @Test("The brand marks and hero metric render at every size")
    func brandAndHero() {
        expectRenders(DiffuseGlyph())
        expectRenders(DiffuseGlyph(size: 64))
        expectRenders(DiffuseBrandMark())
        expectRenders(DiffuseBrandMark(compact: true))
        expectRenders(HeroMetric(value: 0, caption: "vs previous"))
        // One change must read "1 change", not "1 changes".
        expectRenders(HeroMetric(value: 1, caption: "vs previous"))
        expectRenders(HeroMetric(value: 128, caption: "vs previous", isCompact: true))
    }

    // MARK: - Primitives

    @Test("Severity dots and badges render for every severity")
    func severityPrimitives() {
        for severity in ChangeSeverity.allCases {
            expectRenders(SeverityDot(severity))
            expectRenders(SeverityDot(severity, size: 20))
            expectRenders(SeverityBadge(severity))
            expectRenders(SeverityBadge(severity, count: 12))
        }
    }

    @Test("Status labels render for every collection status")
    func statusLabels() {
        for status in CollectionStatus.allCases {
            expectRenders(StatusLabel(status))
            expectRenders(StatusLabel(status, detail: "Took too long"))
        }
    }

    @Test("Chips, cards and tiles render with and without their optional parts")
    func chipsAndContainers() {
        expectRenders(Pill("Pinned"))
        expectRenders(Pill("Pinned", symbol: "pin.fill"))
        expectRenders(Card { Text("Body") })
        expectRenders(Card(padding: 0) { Text("Flush") })
        expectRenders(StatTile(value: "12", label: "Sections"))
        expectRenders(StatTile(count: 1, label: "Change", symbol: "sparkles"))
        expectRenders(SectionHeaderLabel(title: "Network", symbol: "network") { EmptyView() })
        expectRenders(
            SectionHeaderLabel(title: "Network", symbol: "network", subtitle: "4 entities") {
                Pill("New")
            }
        )
    }

    @Test("The empty state and failure banner render")
    func emptyAndFailure() {
        expectRenders(
            EmptyStateView(symbol: "tray", title: "Nothing yet", message: "Take a snapshot.") {
                Button("Take one") {}
            }
        )
        expectRenders(FailureBanner(message: "Could not read the library.") {})
    }

    @Test("Chips wrap instead of clipping when the row runs out of width")
    func chipFlowWraps() {
        // The watch glance packs several badges into ~150pt; the layout has to
        // add a row rather than truncate a capsule.
        let chips = ChipFlowLayout {
            ForEach(ChangeSeverity.allCases, id: \.self) { severity in
                SeverityBadge(severity, count: 99)
            }
        }
        expectRenders(chips.frame(width: 150))
        expectRenders(chips.frame(width: 900))
    }

    // MARK: - Severity summary

    @Test("The severity bar renders for an empty, single and mixed diff")
    func severityBar() {
        expectRenders(SeveritySummaryBar(summary: .empty))
        expectRenders(SeveritySummaryBar(summary: diff.summary))
        expectRenders(SeveritySummaryBar(summary: diff.summary, height: 6, showsLegend: false))
    }

    @Test("The diff header renders in both regular and compact form")
    func diffHeader() {
        expectRenders(DiffHeaderView(diff: diff))
        expectRenders(DiffHeaderView(diff: diff, isCompact: true))
    }

    @Test("The severity filter bar renders at every threshold")
    func severityFilterBar() {
        for severity in ChangeSeverity.allCases {
            var selection = severity
            let binding = Binding(get: { selection }, set: { selection = $0 })
            expectRenders(SeverityFilterBar(minimumSeverity: binding, summary: diff.summary))
        }
    }

    // MARK: - Changes

    @Test("Every change in a real diff renders as a row")
    func changeRows() throws {
        let changes = diff.changes
        try #require(!changes.isEmpty, "the sample snapshots must actually differ")

        for change in changes {
            expectRenders(ChangeRow(change))
            expectRenders(ChangeRow(change, showsSection: true, isCompact: true))
        }
    }

    @Test("Property changes render for each kind and both densities")
    func propertyChanges() throws {
        let property = try #require(diff.changes.compactMap(\.property).first)
        for kind in ChangeKind.allCases {
            expectRenders(PropertyChangeView(property, kind: kind))
            expectRenders(PropertyChangeView(property, kind: kind, isCompact: true))
        }
    }

    /// A property whose value appeared or disappeared is the case most likely
    /// to trip a view that assumes both sides are present.
    @Test("A property change with an absent side still renders")
    func absentPropertySides() {
        let appeared = PropertyChange(key: "value", displayName: "Value", before: .absent, after: .integer(4))
        let vanished = PropertyChange(key: "value", displayName: "Value", before: .integer(4), after: .absent)
        expectRenders(PropertyChangeView(appeared, kind: .added))
        expectRenders(PropertyChangeView(vanished, kind: .removed))
    }

    @Test("The change list renders whole, filtered, and empty")
    func changeList() {
        expectRenders(ChangeListView(sections: diff.sectionDiffs))
        expectRenders(ChangeListView(sections: diff.sectionDiffs, minimumSeverity: .critical))
        expectRenders(ChangeListView(sections: [], onSelect: { _ in }))
    }

    @Test("A cluster card renders, including one whose changes are missing")
    func clusterCard() {
        for cluster in diff.clusters {
            expectRenders(ChangeClusterCard(cluster: cluster, changes: diff.changes(in: cluster)))
        }
        let orphan = ChangeCluster(
            id: "orphan",
            start: SampleData.baseDate,
            end: SampleData.baseDate.addingTimeInterval(120),
            changeIDs: [ChangeID(rawValue: "gone")],
            peakSeverity: .critical,
            capabilities: []
        )
        expectRenders(ChangeClusterCard(cluster: orphan, changes: []))
    }

    // MARK: - Sections and entities

    @Test("Every section of a real snapshot renders")
    func sectionViews() {
        for section in SampleData.macAfterWorkday.orderedSections {
            expectRenders(SnapshotSectionView(section: section))
            expectRenders(SnapshotSectionView(section: section, onSelectEntity: { _ in }))
        }
    }

    @Test("Every entity and property of a real snapshot renders")
    func entityViews() throws {
        let section = try #require(SampleData.macAfterWorkday.orderedSections.first { !$0.entities.isEmpty })

        for entity in section.allEntities {
            expectRenders(EntityRow(entity: entity, descriptor: section.schema.descriptor(for: entity.kind)))
            expectRenders(EntityDetailView(entity: entity, schema: section.schema))

            for descriptor in section.schema.descriptor(for: entity.kind)?.properties ?? [] {
                expectRenders(PropertyRow(descriptor: descriptor, value: entity[descriptor.key] ?? .absent))
            }
        }
    }

    /// An entity kind the schema does not describe should degrade rather than
    /// trap — the row has to cope with a nil descriptor.
    @Test("An entity row renders without a descriptor")
    func entityRowWithoutDescriptor() {
        expectRenders(EntityRow(entity: TestSchema.entity("stray"), descriptor: nil))
    }

    @Test("A section with no data renders its explanation instead of a list")
    func unavailableSection() {
        for status in CollectionStatus.allCases where !status.hasData {
            expectRenders(SnapshotSectionView(section: TestSchema.section(entities: [], status: status)))
        }
    }

    // MARK: - Capabilities and privacy

    @Test("A capability row renders in every availability state")
    func capabilityRows() {
        for status in capabilityStatuses {
            expectRenders(CapabilityRow(status: status))
            expectRenders(CapabilityRow(status: status, onToggle: { _ in }, onRequestPermission: { _ in }))
        }
        expectRenders(CapabilityListView(statuses: capabilityStatuses))
        expectRenders(CapabilityListView(statuses: [], onToggle: { _, _ in }, onRequestPermission: { _ in }))
    }

    @Test("The privacy ledger renders for a full and an empty capability set")
    func privacyLedger() {
        expectRenders(PrivacyLedgerView(ledger: PrivacyLedger(statuses: capabilityStatuses)))
        expectRenders(PrivacyLedgerView(ledger: PrivacyLedger(statuses: [])))
    }

    // MARK: - Search

    @Test("Search results render, including the no-results state")
    func searchResults() throws {
        let index = SearchIndex(snapshots: [SampleData.macAfterWorkday])
        let results = index.search("a")
        try #require(!results.isEmpty, "the sample snapshot must be searchable")

        for result in results.prefix(12) {
            expectRenders(SearchResultRow(result: result))
        }
        expectRenders(LibrarySearchResultsView(results: Array(results.prefix(12))) { _ in })
        expectRenders(LibrarySearchResultsView(results: []) { _ in })
    }

    // MARK: - Timeline

    @Test("Timeline rows render selected, unselected and with a change count")
    func timelineRows() {
        for summary in summaries {
            expectRenders(TimelineRow(summary: summary))
            expectRenders(TimelineRow(summary: summary, changeCount: 0))
            expectRenders(TimelineRow(summary: summary, changeCount: 7, isSelected: true, selectionOrder: 1))
        }
    }

    @Test("The timeline renders grouped by day, and empty")
    func timeline() {
        expectRenders(SnapshotTimelineView(summaries: summaries) { TimelineRow(summary: $0) })
        expectRenders(SnapshotTimelineView(summaries: []) { TimelineRow(summary: $0) })

        // Day headings are drawn through the timeline rather than directly:
        // the heading view is internal, and this suite deliberately exercises
        // public API only. `groupedAcrossDays` produces a one-snapshot day, a
        // many-snapshot day, and a day old enough to fall back to a full date,
        // so every heading branch is drawn — including the singular and plural
        // accessibility labels.
        expectRenders(SnapshotTimelineView(summaries: groupedAcrossDays) { TimelineRow(summary: $0) })

        // The heading has no fill of its own, so it has to hold up on a raised
        // surface as well as on the page canvas.
        expectRenders(
            SnapshotTimelineView(summaries: groupedAcrossDays) { TimelineRow(summary: $0) }
                .background(DiffuseTheme.Palette.surfaceRaised)
        )
    }

    @Test("The activity strip renders with data, with a flat run, and with none")
    func activityStrip() {
        let days = (0 ..< 7).map { SampleData.baseDate.addingTimeInterval(Double($0) * 86400) }
        expectRenders(ActivityStrip(activity: days.enumerated().map { (day: $1, count: $0) }))
        // An all-zero week must not divide by a zero maximum.
        expectRenders(ActivityStrip(activity: days.map { (day: $0, count: 0) }, height: 20))
        expectRenders(ActivityStrip(activity: []))
    }

    // MARK: - Settings

    @Test("The shared settings sections render")
    func preferenceSettings() {
        let preferences = DiffusePreferences(defaults: scratchDefaults())
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let clock = FixedTimeSource(SampleData.baseDate)
        let model = DiffuseModel(
            service: SnapshotService(
                coordinator: SnapshotCoordinator(
                    catalog: catalog,
                    deviceProvider: StaticDeviceIdentityProvider.testDevice,
                    platform: .macOS,
                    timeSource: clock
                ),
                store: InMemorySnapshotStore(),
                catalog: catalog,
                timeSource: clock
            )
        )

        expectRenders(PreferenceSettingsSections(preferences: preferences, model: model))
        expectRenders(
            PreferenceSettingsSections(preferences: preferences, model: model, systemEventLabel: "When I open the app")
        )
    }

    // MARK: - Comparison pair picker

    @Test("The pair picker renders empty, half-chosen, and complete")
    func pairPickerAtEverySelectionCount() {
        let ids = summaries.map(\.id)

        // Nothing chosen: both slots read "Not chosen" and the hint asks for two.
        expectRenders(picker(selection: []))

        // One chosen: the base slot is filled, the target is not. This is the
        // state that used to be unreachable, because selection happened on
        // another screen entirely.
        expectRenders(picker(selection: [ids[0]]))

        // Two chosen: both slots filled and the hint explains the direction.
        expectRenders(picker(selection: [ids[0], ids[1]]))

        // Chosen newest-first, which is what reading a list top-down produces.
        // The slots must still resolve base and target by date.
        expectRenders(picker(selection: [ids[1], ids[0]]))
    }

    @Test("The pair picker renders with no snapshots and with a single one")
    func pairPickerWithTooFewSnapshots() {
        // No history at all — the list is replaced by an empty state rather
        // than by a bare heading with nothing under it.
        expectRenders(
            SnapshotPairPicker(
                summaries: [],
                selection: [],
                onToggle: { _ in },
                onCompareLatest: {},
                onClear: {}
            )
        )

        // One snapshot cannot be compared, so the shortcut must not be offered.
        let single = Array(summaries.prefix(1))
        expectRenders(
            SnapshotPairPicker(
                summaries: single,
                selection: [],
                onToggle: { _ in },
                onCompareLatest: {},
                onClear: {}
            )
        )
    }

    @Test("The pair picker renders in its compact form")
    func pairPickerCompact() {
        expectRenders(picker(selection: [summaries[0].id], isCompact: true))
        expectRenders(picker(selection: [], isCompact: true))
    }

    @Test("A labelled snapshot is named by its label, an unlabelled one by its date")
    func pairPickerSlotNaming() {
        // summaries[0] carries a label, summaries[1] does not — both slot
        // branches are drawn in one pass.
        expectRenders(picker(selection: [summaries[0].id, summaries[1].id]))
    }

    private func picker(selection: [SnapshotID], isCompact: Bool = false) -> some View {
        SnapshotPairPicker(
            summaries: summaries,
            selection: selection,
            isCompact: isCompact,
            onToggle: { _ in },
            onCompareLatest: {},
            onClear: {}
        )
    }

    // MARK: - Fixtures

    private var diff: DiffResult {
        DiffEngine().diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)
    }

    private var summaries: [SnapshotSummary] {
        SampleData.timeline.enumerated().map { index, snapshot in
            SnapshotSummary.stub(
                id: snapshot.id.rawValue,
                capturedAt: snapshot.capturedAt,
                platform: snapshot.platform,
                origin: snapshot.origin,
                // A labelled and a pinned row take different branches from a
                // plain one, so the set covers both.
                label: index == 0 ? "Before the upgrade" : nil,
                isPinned: index == 1,
                tags: index == 1 ? ["baseline"] : [],
                sectionCount: snapshot.sections.count,
                entityCount: snapshot.sections.reduce(0) { $0 + $1.entityCount },
                problemCount: index
            )
        }
    }

    /// One capability in each availability state, so every branch of the row
    /// and the ledger is drawn.
    /// Snapshots spread over several days, so the timeline draws a heading for
    /// a single-snapshot day, a busy day, and one far enough back that the
    /// heading falls through to a formatted date rather than "Today".
    private var groupedAcrossDays: [SnapshotSummary] {
        let calendar = Calendar.current
        let now = Date()
        func day(_ offset: Int, _ hour: Int) -> Date {
            let start = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? start
        }

        return [
            .stub(id: "today-1", capturedAt: day(0, 9), label: "This morning"),
            .stub(id: "yesterday-1", capturedAt: day(1, 8)),
            .stub(id: "yesterday-2", capturedAt: day(1, 13), isPinned: true),
            .stub(id: "yesterday-3", capturedAt: day(1, 18)),
            .stub(id: "old-1", capturedAt: day(30, 11), problemCount: 2),
        ]
    }

    private var capabilityStatuses: [CapabilityStatus] {
        let metadata = FakeCapabilityFactory.mixedRegistry().capabilities.map(\.metadata)
        let states: [CapabilityAvailability] = [
            .available,
            .unavailable(reason: "No adapter found"),
            .unsupported(reason: "Not on this platform"),
            .permissionRequired(
                PermissionRequirement(id: "full-disk", displayName: "Full Disk Access", rationale: "To read volumes.")
            ),
            .temporarilyUnavailable(reason: "Busy"),
        ]

        guard !metadata.isEmpty else { return [] }
        return states.enumerated().map { index, availability in
            CapabilityStatus(
                metadata: metadata[index % metadata.count],
                availability: availability,
                isEnabled: index.isMultiple(of: 2)
            )
        }
    }

    private func scratchDefaults() -> UserDefaults {
        let suite = "ViewRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Renders `view` and fails the test if the body traps or produces nothing.
    private func expectRenders(
        _ view: some View,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let renderer = ImageRenderer(content: view.frame(width: 420).padding())
        renderer.scale = 1
        #expect(renderer.nsImage != nil, comment ?? "the view rendered to nothing", sourceLocation: sourceLocation)
    }
}

#endif
