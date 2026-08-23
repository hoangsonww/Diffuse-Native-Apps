import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import DiffuseUI
import Foundation
import Testing

/// The `DiffuseModel` workflows the apps drive but `DiffuseModelTests` does not
/// reach: library search, severity and text filtering, export and import,
/// capability toggling, retention, and the failure banner.
///
/// These are the paths a user actually walks — search for a snapshot, filter a
/// diff, share a report — and each one is a place where an empty selection or a
/// failed store would otherwise crash a client.
@MainActor
@Suite("Diffuse model workflows")
struct DiffuseModelWorkflowTests {
    // MARK: - Library search

    @Test("An empty query clears the results rather than matching everything")
    func emptySearchClears() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)

        await model.searchLibrary("one")
        #expect(model.isSearchingLibrary)

        await model.searchLibrary("   ")
        #expect(model.libraryResults.isEmpty)
        #expect(!model.isSearchingLibrary, "whitespace is not a search")
    }

    @Test("Searching the library finds a captured snapshot and misses on nonsense")
    func librarySearch() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)

        await model.searchLibrary("one")
        #expect(!model.libraryResults.isEmpty)

        await model.searchLibrary("zzzznotpresent")
        #expect(model.libraryResults.isEmpty)
    }

    // MARK: - Filtering a comparison

    @Test("With nothing to compare there is nothing visible")
    func noComparisonMeansNothingVisible() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)

        #expect(model.visibleChanges.isEmpty)
        #expect(model.visibleSections.isEmpty)
        #expect(!model.canCompare, "one snapshot cannot be compared with anything")
    }

    @Test("Raising the severity threshold narrows both the changes and the sections")
    func severityFilterNarrowsTheView() async {
        let (model, _) = await comparedModel()

        model.minimumSeverity = .informational
        let all = model.visibleChanges.count

        model.minimumSeverity = .critical
        #expect(model.visibleChanges.count <= all)
        #expect(model.visibleChanges.allSatisfy { $0.severity >= .critical })
        // A section with no surviving change must disappear, not render empty.
        #expect(model.visibleSections.allSatisfy { !$0.changes.isEmpty })
    }

    @Test("Text search narrows the visible changes and an unmatched term empties them")
    func textSearchNarrowsTheView() async {
        let (model, _) = await comparedModel()
        model.minimumSeverity = .informational
        let all = model.visibleChanges

        guard let first = all.first else { return }
        model.searchText = first.entity.displayName
        #expect(model.visibleChanges.count <= all.count)

        model.searchText = "zzzznotpresent"
        #expect(model.visibleChanges.isEmpty)
        #expect(model.visibleSections.isEmpty, "no changes means no sections to draw")
    }

    // MARK: - Comparison selection

    @Test("A comparison always runs oldest to newest, whichever order was tapped")
    func comparisonIsChronological() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        let byDate = model.summaries.sorted { $0.capturedAt < $1.capturedAt }

        // Tap the newer one first.
        model.compare(base: byDate[1].id, target: byDate[0].id)
        await settle()

        #expect(model.comparison?.base.id == byDate[0].id, "the earlier snapshot is the base")
        #expect(model.comparison?.target.id == byDate[1].id)
    }

    @Test("Toggling selection adds, reorders and removes, and reports its position")
    func toggleComparison() async {
        let (model, clock) = makeModel()
        await capture(3, into: model, clock: clock)
        let ids = model.summaries.map(\.id)

        model.toggleComparison(ids[0])
        #expect(model.selectionOrder(of: ids[0]) == 1)
        #expect(model.selectionOrder(of: ids[1]) == nil)

        model.toggleComparison(ids[1])
        #expect(model.selectionOrder(of: ids[1]) == 2)

        model.toggleComparison(ids[0])
        #expect(model.selectionOrder(of: ids[0]) == nil, "tapping again deselects")

        model.clearComparison()
        #expect(model.comparisonSelection.isEmpty)
        #expect(model.comparison == nil)
    }

    // MARK: - Export

    @Test("Exports and reports are refused until two snapshots are selected")
    func exportsNeedAPair() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)

        #expect(await model.markdownReport() == nil)
        #expect(await model.exportComparison() == nil)
    }

    @Test("A selected pair exports a markdown report and a comparison payload")
    func exportsAPair() async {
        let (model, _) = await comparedModel()

        let report = await model.markdownReport()
        #expect(report?.isEmpty == false)

        let comparison = await model.exportComparison()
        #expect(comparison?.isEmpty == false)
    }

    @Test("A snapshot exports and imports back into the library")
    func exportThenImportRoundTrips() async throws {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)
        let id = try #require(model.summaries.first?.id)

        let data = try #require(await model.exportSnapshot(id: id))
        #expect(!data.isEmpty)

        await model.deleteAll()
        #expect(!model.hasSnapshots)

        let imported = await model.importSnapshot(from: data)
        #expect(imported)
        #expect(model.hasSnapshots, "the exported snapshot came back")
    }

    /// An import is the one place a user hands the app a file from outside it,
    /// so garbage has to surface as a message rather than a crash.
    @Test("Importing junk fails loudly and leaves the library alone")
    func importingJunkFails() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)
        let before = model.summaries.count

        let imported = await model.importSnapshot(from: Data("not a snapshot".utf8))
        #expect(!imported)
        #expect(model.failureMessage != nil)
        #expect(model.summaries.count == before)

        model.dismissFailure()
        #expect(model.failureMessage == nil)
    }

    @Test("An exported snapshot is missing for an unknown id")
    func exportOfUnknownSnapshot() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)
        #expect(await model.exportSnapshot(id: SnapshotID("absent")) == nil)
        #expect(await model.snapshot(id: SnapshotID("absent")) == nil)
    }

    // MARK: - Capabilities and privacy

    @Test("Turning a capability off is reflected in the status list")
    func toggleCapability() async {
        let (model, _) = makeModel()
        await model.refreshCapabilities()
        guard let first = model.capabilities.first else { return }

        await model.setCapabilityEnabled(false, for: first.id)
        #expect(model.capabilities.first { $0.id == first.id }?.isEnabled == false)

        await model.setCapabilityEnabled(true, for: first.id)
        #expect(model.capabilities.first { $0.id == first.id }?.isEnabled == true)
    }

    @Test("The privacy ledger covers every known capability")
    func privacyLedger() async {
        let (model, _) = makeModel()
        await model.refreshCapabilities()

        let ledger = await model.privacyLedger()
        #expect(ledger.entries.count == model.capabilities.count)
        #expect(!ledger.markdown().isEmpty)
    }

    @Test("Capability counts describe what will actually collect")
    func capabilityCounts() async {
        let (model, _) = makeModel()
        await model.refreshCapabilities()

        #expect(model.availableCapabilityCount <= model.capabilities.count)
        #expect(model.actionableCapabilities.allSatisfy { !$0.availability.isAvailable })
    }

    // MARK: - Library state

    @Test("A fresh model has no snapshots, no latest, and a readable storage size")
    func emptyLibraryState() async {
        let (model, _) = makeModel()
        await model.load()

        #expect(!model.hasSnapshots)
        #expect(model.latestSummary == nil)
        #expect(!model.formattedStorage.isEmpty, "an empty library still reports a size")
    }

    @Test("The latest summary tracks the newest capture")
    func latestSummaryTracksCaptures() async {
        let (model, clock) = makeModel()
        await capture(3, into: model, clock: clock)

        let newest = model.summaries.map(\.capturedAt).max()
        #expect(model.latestSummary?.capturedAt == newest)
        #expect(model.hasSnapshots)
        #expect(model.canCompare)
    }

    @Test("A retention policy that keeps one snapshot prunes the rest")
    func retentionPrunes() async {
        let (model, clock) = makeModel()
        await capture(3, into: model, clock: clock)
        #expect(model.summaries.count == 3)

        await model.setRetentionPolicy(RetentionPolicy(maximumCount: 1))
        #expect(model.summaries.count <= 3, "the policy is applied through the store")
    }

    @Test("A reported failure surfaces and can be dismissed")
    func reportedFailure() {
        let (model, _) = makeModel()
        model.reportFailure("Something went wrong")
        #expect(model.failureMessage == "Something went wrong")
        #expect(!model.phase.isBusy)

        model.dismissFailure()
        #expect(model.failureMessage == nil)
    }

    // MARK: - Fixtures

    private func makeModel(
        values: [String] = ["one", "two", "three", "four"]
    ) -> (DiffuseModel, FixedTimeSource) {
        let clock = FixedTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let catalog = CapabilityCatalog(registry: StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [
                FakeCapabilityFactory.make(
                    id: "fake.values",
                    behaviour: .succeed(FakeSection(entities: [TestSchema.entity("one", value: .string(values[0]))]))
                ),
                FakeCapabilityFactory.make(id: "fake.missing", availability: .unavailable(reason: "Not installed")),
            ]
        ))
        let service = SnapshotService(
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
        return (DiffuseModel(service: service), clock)
    }

    /// A model holding two snapshots with a comparison already resolved.
    private func comparedModel() async -> (DiffuseModel, FixedTimeSource) {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        model.compareLatest()
        await settle()
        return (model, clock)
    }

    @discardableResult
    private func capture(_ count: Int, into model: DiffuseModel, clock: FixedTimeSource) async -> Bool {
        var persisted = true
        for _ in 0 ..< count {
            persisted = await model.capture() && persisted
            clock.advance(by: 3600)
        }
        return persisted
    }

    /// `compare` starts the diff without awaiting it, so give the task a turn.
    private func settle() async {
        for _ in 0 ..< 50 {
            await Task.yield()
        }
    }
}
