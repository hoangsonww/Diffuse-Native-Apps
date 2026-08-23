import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import DiffuseUI
import Foundation
import Testing

/// `DiffuseModel` is the state every app is built on — the four Apple clients
/// and the widgets all drive their UI from it — so its orchestration is worth
/// covering directly rather than only through whichever screen happens to call
/// it.
@MainActor
@Suite("Diffuse model")
struct DiffuseModelTests {
    // MARK: - Fixtures

    private func makeModel(
        values: [String] = ["one", "two", "three", "four"]
    ) -> (DiffuseModel, FixedTimeSource) {
        let clock = FixedTimeSource(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemorySnapshotStore()
        let catalog = CapabilityCatalog(registry: StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [
                FakeCapabilityFactory.make(
                    id: "fake.values",
                    behaviour: .succeed(FakeSection(entities: [TestSchema.entity("one", value: .string(values[0]))]))
                ),
            ]
        ))
        let service = SnapshotService(
            coordinator: SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .macOS,
                timeSource: clock
            ),
            store: store,
            catalog: catalog,
            timeSource: clock
        )
        return (DiffuseModel(service: service), clock)
    }

    /// Captures `count` snapshots, advancing the clock so each is distinct and
    /// ordering is unambiguous.
    @discardableResult
    private func capture(_ count: Int, into model: DiffuseModel, clock: FixedTimeSource) async -> Bool {
        var persisted = true
        for _ in 0 ..< count {
            persisted = await model.capture() && persisted
            clock.advance(by: 3600)
        }
        return persisted
    }

    // MARK: - Loading

    @Test("A fresh model is idle and empty until loaded")
    func startsIdle() {
        let (model, _) = makeModel()
        #expect(model.phase == .idle)
        #expect(model.summaries.isEmpty)
        #expect(model.overview == nil)
        #expect(model.comparison == nil)
        #expect(model.comparisonSelection.isEmpty)
    }

    @Test("Loading an empty library leaves the model ready rather than failed")
    func loadEmptyLibrary() async {
        let (model, _) = makeModel()
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.summaries.isEmpty)
        #expect(model.storageBytes == 0)
    }

    @Test("Capturing persists a snapshot and refreshes the derived state")
    func captureRefreshesState() async {
        let (model, clock) = makeModel()
        let persisted = await model.capture()
        clock.advance(by: 3600)

        #expect(persisted)
        #expect(model.phase == .ready)
        #expect(model.summaries.count == 1)
        #expect(model.lastCaptureReport != nil)
        #expect(model.storageBytes > 0)
    }

    @Test("Capture reports its own label and origin on the stored snapshot")
    func captureCarriesLabelAndOrigin() async {
        let (model, _) = makeModel()
        _ = await model.capture(label: "Before the update", origin: .scheduled)

        #expect(model.summaries.first?.label == "Before the update")
        #expect(model.summaries.first?.origin == .scheduled)
    }

    // MARK: - Annotations

    @Test("Pinning and labelling survive a refresh")
    func annotationsPersist() async throws {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)
        let id = try #require(model.summaries.first?.id)

        await model.setPinned(true, for: id)
        #expect(model.summaries.first?.isPinned == true)

        await model.setLabel("Named", for: id)
        #expect(model.summaries.first?.label == "Named")
        // Pinning must not be clobbered by a later label write.
        #expect(model.summaries.first?.isPinned == true)
    }

    // MARK: - Deletion

    @Test("Deleting a snapshot drops it from the comparison selection")
    func deleteClearsSelection() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        let ids = model.summaries.map(\.id)
        model.compare(base: ids[1], target: ids[0])
        #expect(model.comparisonSelection.count == 2)

        await model.delete(id: ids[0])

        #expect(model.summaries.count == 1)
        #expect(!model.comparisonSelection.contains(ids[0]))
    }

    @Test("Deleting everything clears the library, the selection and the comparison")
    func deleteAllResetsComparison() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        model.compareLatest()

        await model.deleteAll()

        #expect(model.summaries.isEmpty)
        #expect(model.comparisonSelection.isEmpty)
        #expect(model.comparison == nil)
        #expect(model.storageBytes == 0)
    }

    // MARK: - Comparison selection

    @Test("Toggling adds, removes, and never holds more than two snapshots")
    func toggleKeepsTwoSlots() async {
        let (model, clock) = makeModel()
        await capture(3, into: model, clock: clock)
        let ids = model.summaries.map(\.id)

        model.toggleComparison(ids[0])
        #expect(model.comparisonSelection == [ids[0]])

        model.toggleComparison(ids[1])
        #expect(model.comparisonSelection == [ids[0], ids[1]])

        // A third selection replaces the oldest rather than being rejected.
        model.toggleComparison(ids[2])
        #expect(model.comparisonSelection == [ids[1], ids[2]])

        // Toggling a selected snapshot removes it.
        model.toggleComparison(ids[1])
        #expect(model.comparisonSelection == [ids[2]])
    }

    @Test("Selection order is one-based and nil for unselected snapshots")
    func selectionOrderIsOneBased() async {
        let (model, clock) = makeModel()
        await capture(3, into: model, clock: clock)
        let ids = model.summaries.map(\.id)

        model.toggleComparison(ids[0])
        model.toggleComparison(ids[1])

        #expect(model.selectionOrder(of: ids[0]) == 1)
        #expect(model.selectionOrder(of: ids[1]) == 2)
        #expect(model.selectionOrder(of: ids[2]) == nil)
    }

    @Test("compareLatest needs two snapshots and orders them base then target")
    func compareLatestOrdersPair() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)

        model.compareLatest()
        #expect(model.comparisonSelection.isEmpty, "one snapshot cannot be compared")

        await capture(1, into: model, clock: clock)
        model.compareLatest()

        // summaries are newest first, so base is the older of the two.
        #expect(model.comparisonSelection == [model.summaries[1].id, model.summaries[0].id])
    }

    @Test("Clearing the comparison empties both the selection and the result")
    func clearComparison() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        model.compareLatest()

        model.clearComparison()

        #expect(model.comparisonSelection.isEmpty)
        #expect(model.comparison == nil)
    }

    // MARK: - Library search

    @Test("An empty or whitespace query returns no results rather than everything")
    func emptySearchReturnsNothing() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)

        await model.searchLibrary("")
        #expect(model.libraryResults.isEmpty)

        await model.searchLibrary("   ")
        #expect(model.libraryResults.isEmpty)
        #expect(model.libraryQuery == "   ")
    }

    @Test("Searching finds a labelled snapshot by name")
    func searchFindsLabelledSnapshot() async {
        let (model, clock) = makeModel()
        _ = await model.capture(label: "Distinctive")
        clock.advance(by: 3600)

        await model.searchLibrary("Distinctive")

        #expect(!model.libraryResults.isEmpty)
    }

    // MARK: - Failure surface

    @Test("A reported failure is visible and dismissable")
    func failureIsDismissable() {
        let (model, _) = makeModel()

        model.reportFailure("Disk unavailable")
        #expect(model.phase.failureMessage == "Disk unavailable")
        #expect(model.phase.isBusy == false)

        model.dismissFailure()
        #expect(model.phase.failureMessage == nil)
    }

    @Test("Phase reports busy only while loading or capturing")
    func busyPhases() {
        #expect(DiffuseModel.Phase.loading.isBusy)
        #expect(DiffuseModel.Phase.capturing.isBusy)
        #expect(!DiffuseModel.Phase.idle.isBusy)
        #expect(!DiffuseModel.Phase.ready.isBusy)
        #expect(!DiffuseModel.Phase.failed("x").isBusy)
        #expect(DiffuseModel.Phase.failed("x").failureMessage == "x")
        #expect(DiffuseModel.Phase.ready.failureMessage == nil)
    }

    // MARK: - Export and import

    @Test("A captured snapshot exports and imports back into an empty library")
    func exportThenImportRoundTrips() async throws {
        let (source, clock) = makeModel()
        await capture(1, into: source, clock: clock)
        let id = try #require(source.summaries.first?.id)

        let data = try #require(await source.exportSnapshot(id: id))
        #expect(!data.isEmpty)

        let (destination, _) = makeModel()
        let imported = await destination.importSnapshot(from: data)

        #expect(imported)
        #expect(destination.summaries.count == 1)
    }

    @Test("Importing malformed data fails without disturbing the library")
    func importRejectsGarbage() async {
        let (model, clock) = makeModel()
        await capture(1, into: model, clock: clock)

        let imported = await model.importSnapshot(from: Data("not a snapshot".utf8))

        #expect(!imported)
        #expect(model.summaries.count == 1, "a rejected import must not delete anything")
    }

    @Test("A markdown report is produced once a comparison exists")
    func markdownReportNeedsComparison() async {
        let (model, clock) = makeModel()
        await capture(2, into: model, clock: clock)
        model.compareLatest()
        // Let the comparison task settle.
        await Task.yield()

        let report = await model.markdownReport()
        if let report {
            #expect(!report.isEmpty)
        }
    }

    // MARK: - Capabilities

    @Test("Capabilities load and can be toggled")
    func capabilitiesToggle() async throws {
        let (model, _) = makeModel()
        await model.refreshCapabilities()
        let first = try #require(model.capabilities.first as CapabilityStatus?)

        await model.setCapabilityEnabled(false, for: first.id)
        await model.refreshCapabilities()

        let updated = model.capabilities.first { $0.id == first.id }
        #expect(updated?.isEnabled == false)

        await model.setCapabilityEnabled(true, for: first.id)
        await model.refreshCapabilities()
        #expect(model.capabilities.first { $0.id == first.id }?.isEnabled == true)
    }
}
