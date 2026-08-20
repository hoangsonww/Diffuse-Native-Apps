import DiffuseCapabilities
import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Library pipeline")
struct LibraryPipelineTests {
    private func service(
        store: any SnapshotStore,
        clock: FixedTimeSource,
        value: String
    ) -> SnapshotService {
        let catalog = CapabilityCatalog(registry: StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [
                FakeCapabilityFactory.make(
                    behaviour: .succeed(FakeSection(entities: [TestSchema.entity(
                        "one",
                        name: "Alpha",
                        value: .string(value)
                    )]))
                ),
            ]
        ))
        return SnapshotService(
            coordinator: SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .macOS,
                timeSource: clock
            ),
            store: store,
            catalog: catalog,
            timeSource: clock,
            retentionPolicy: .unlimited
        )
    }

    @Test("Five captures produce a four-step timeline and searchable history")
    func manyCaptures() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)

        var ids: [SnapshotID] = []
        for index in 0 ..< 5 {
            let report = try await service(store: store, clock: clock, value: "v\(index)").capture(label: "c\(index)")
            ids.append(report.snapshot.id)
            clock.advance(by: 3600)
        }

        #expect(try await store.count() == 5)
        let snapshots = try await store.snapshots(matching: .all)
        let timeline = ChangeTimeline(snapshots: snapshots)
        #expect(timeline.steps.count == 4)
        #expect(timeline.totalChanges == 4)
        #expect(timeline.history(of: EntityIdentity(kind: TestSchema.widget, value: "one")).count == 4)

        let hits = SearchIndex(snapshots: snapshots).search("alpha")
        #expect(!hits.isEmpty)
    }

    @Test("Export report matches ReportRenderer for the same pair")
    func exportParity() async throws {
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        let store = InMemorySnapshotStore()
        let first = try await service(store: store, clock: clock, value: "old").capture(label: "Before")
        clock.advance(by: 60)
        let second = try await service(store: store, clock: clock, value: "new").capture(label: "After")
        let svc = service(store: store, clock: clock, value: "new")
        let exported = try await svc.exportReport(base: first.snapshot.id, target: second.snapshot.id)
        let direct = ReportRenderer.markdown(
            for: DiffEngine().diff(base: first.snapshot, target: second.snapshot)
        )
        #expect(exported == direct)
        #expect(exported.contains("# Diffuse Report"))
        #expect(exported.contains("Before"))
    }

    @Test("Imported snapshots are searchable and keep travelling schema")
    func importThenSearch() async throws {
        let original = SampleData.macBaseline
        let data = try SnapshotCoding.encode(original)
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let service = SnapshotService(
            coordinator: SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .iOS,
                timeSource: FixedTimeSource(SnapshotBuilder.referenceDate)
            ),
            store: InMemorySnapshotStore(),
            catalog: catalog
        )
        let imported = try await service.importSnapshot(from: data)
        #expect(imported.id != original.id)
        #expect(imported.origin == .imported)
        let hits = try await service.search("mac")
        #expect(!hits.isEmpty)
        #expect(SnapshotValidator.validate(imported).isEmpty)
    }

    @Test("Retention on a file store deletes exactly the planned identifiers")
    func fileStoreRetention() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let now = SnapshotBuilder.referenceDate
        for index in 0 ..< 5 {
            try await store.save(
                SnapshotBuilder(
                    id: "r\(index)",
                    capturedAt: now.addingTimeInterval(-Double(index) * 86400)
                )
                .withWidgets([TestSchema.entity("one")])
                .build()
            )
        }
        let plan = try await store.applyRetention(
            RetentionPolicy(age: .days(2), maximumBytes: nil),
            now: now
        )
        #expect(!plan.deletions.contains("r0"))
        #expect(try await store.count() == 5 - plan.deletions.count)
        for id in plan.deletions {
            #expect(try await store.snapshot(id: id) == nil)
        }
    }

    @Test("Query paging on a live file store is stable")
    func fileStorePaging() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        for index in 0 ..< 6 {
            try await store.save(
                SnapshotBuilder(
                    id: "p\(index)",
                    capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(Double(index))
                )
                .on(index.isMultiple(of: 2) ? .macOS : .iOS)
                .withWidgets([TestSchema.entity("one")])
                .build()
            )
        }
        let page = try await store.summaries(matching: SnapshotQuery(platforms: [.macOS], limit: 2))
        #expect(page.count == 2)
        #expect(page.allSatisfy { $0.platform == .macOS })
        let newest = try await store.latest()
        #expect(newest?.id == SnapshotID("p5"))
    }
}

@Suite("Golden fixture properties")
struct FixturePropertyTests {
    @Test("Every snapshot fixture round-trips and self-diffs empty")
    func fixturesAreStable() throws {
        for name in FixtureGenerator.snapshots.map(\.name) {
            let snapshot = try #require(FixtureGenerator.snapshot(named: name))
            #expect(SnapshotValidator.validate(snapshot).isEmpty, "\(name)")
            let encoded = try SnapshotCoding.encode(snapshot)
            #expect(try SnapshotCoding.decodeSnapshot(encoded) == snapshot, "\(name)")
            #expect(DiffEngine().selfDiff(snapshot).isEmpty, "\(name)")
        }
    }

    @Test("Every expected diff fixture matches a live engine run")
    func expectedDiffsAreLive() throws {
        for spec in FixtureGenerator.diffs {
            let generated = try #require(FixtureGenerator.expectedDiff(named: spec.name))
            #expect(
                generated.summary.totalChanges == generated.changes.filter { $0.kind != .unchanged }.count,
                "\(spec.name)"
            )
        }
    }

    @Test("Sample data timeline is ordered and non-empty")
    func sampleTimeline() {
        #expect(SampleData.timeline.count >= 2)
        let times = SampleData.timeline.map(\.capturedAt)
        #expect(times == times.sorted())
        let timeline = ChangeTimeline(snapshots: SampleData.timeline)
        #expect(!timeline.steps.isEmpty)
        #expect(timeline.totalChanges == timeline.allChanges.count)
    }
}
