import DiffuseCapabilities
import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot service")
struct DomainSnapshotServiceTests {
    private func makeService(
        store: any SnapshotStore = InMemorySnapshotStore(),
        clock: FixedTimeSource = FixedTimeSource(SnapshotBuilder.referenceDate),
        retention: RetentionPolicy = .unlimited,
        value: String = "alpha"
    ) -> (SnapshotService, FixedTimeSource) {
        let catalog = CapabilityCatalog(registry: StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [
                FakeCapabilityFactory.make(
                    id: "fake.healthy",
                    behaviour: .succeed(FakeSection(entities: [TestSchema.entity("one", value: .string(value))]))
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
            timeSource: clock,
            retentionPolicy: retention
        )
        return (service, clock)
    }

    @Test("Overview is empty until two snapshots exist")
    func overviewEmptyThenPopulated() async throws {
        let (service, clock) = makeService()
        let empty = try await service.overview()
        #expect(empty.latest == nil)
        #expect(!empty.hasComparison)
        #expect(empty.snapshotCount == 0)

        try await service.capture(label: "First")
        let one = try await service.overview()
        #expect(one.latest != nil)
        #expect(!one.hasComparison)

        clock.advance(by: 60)
        try await service.capture(label: "Second")
        let two = try await service.overview()
        #expect(two.hasComparison)
        #expect(two.snapshotCount == 2)
        #expect(two.latest?.label == "Second")
        #expect(two.previous?.label == "First")
    }

    @Test("Import assigns a new id, marks origin imported, and tags the snapshot")
    func importRewritesIdentity() async throws {
        let (service, _) = makeService()
        let original = SnapshotBuilder(id: "original")
            .labelled("From the other Mac")
            .withWidgets([TestSchema.entity("one")])
            .build()
        let imported = try await service.importSnapshot(from: SnapshotCoding.encode(original))
        #expect(imported.id != original.id)
        #expect(imported.origin == .imported)
        #expect(imported.tags.contains("imported"))
        #expect(imported.label == "From the other Mac")
        #expect(try await service.count() == 1)
    }

    @Test("Unchanged automatic captures can be skipped")
    func skipIfUnchanged() async throws {
        let (service, clock) = makeService()
        let first = try await service.capture(origin: .scheduled)
        #expect(first.didPersist)
        clock.advance(by: 60)
        let second = try await service.capture(origin: .scheduled, skipIfUnchanged: true)
        #expect(!second.didPersist)
        #expect(try await service.count() == 1)
    }

    @Test("Manual captures still persist when skipIfUnchanged is set")
    func manualNeverSkipped() async throws {
        let (service, clock) = makeService()
        try await service.capture(origin: .manual)
        clock.advance(by: 60)
        let second = try await service.capture(origin: .manual, skipIfUnchanged: true)
        #expect(second.didPersist)
        #expect(try await service.count() == 2)
    }

    @Test("Library search is exposed through the service")
    func serviceSearch() async throws {
        let (service, _) = makeService()
        try await service.capture()
        let results = try await service.search("widgets")
        #expect(!results.isEmpty)
        #expect(try await service.search("   ").isEmpty)
    }

    @Test("Annotate, pin and delete round-trip through the store")
    func annotateAndDelete() async throws {
        let (service, _) = makeService()
        let report = try await service.capture()
        try await service.annotate(
            id: report.snapshot.id,
            with: SnapshotAnnotation(label: "Keep", isPinned: true, tags: ["lab"])
        )
        let updated = try await service.snapshot(id: report.snapshot.id)
        #expect(updated?.label == "Keep")
        #expect(updated?.isPinned == true)
        #expect(updated?.tags == ["lab"])

        try await service.delete(id: report.snapshot.id)
        #expect(try await service.count() == 0)
        try await service.capture()
        try await service.deleteAll()
        #expect(try await service.count() == 0)
    }

    @Test("Export applies redaction to snapshots, diffs and reports")
    func exportRedaction() async throws {
        let schema = TestSchema.make(privacy: .sensitive)
        let snapshot = SnapshotBuilder(id: "s")
            .withWidgets([TestSchema.entity("one", name: "HomeNet", value: .string("secret-ssid"))], schema: schema)
            .build()
        let store = InMemorySnapshotStore(snapshots: [snapshot])
        let (service, _) = makeService(store: store)
        let data = try await service.exportSnapshot(id: snapshot.id, redaction: .standard)
        let decoded = try SnapshotCoding.decodeSnapshot(data)
        #expect(decoded.sections[0].entities[0].properties["value"] == .string("‹redacted›"))
        #expect(decoded.metadata.appliedRedaction == .standard)
    }

    @Test("Retention after capture keeps the newest snapshot")
    func retentionKeepsNewest() async throws {
        let policy = RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: 1, protectsLabelled: false)
        let (service, clock) = makeService(retention: policy)
        try await service.capture(label: "First")
        clock.advance(by: 60)
        try await service.capture(label: "Second")
        let remaining = try await service.summaries()
        #expect(remaining.count == 1)
        #expect(remaining[0].label == "Second")
    }

    @Test("Diffing stored snapshots matches diffing them directly")
    func storedDiff() async throws {
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        let store = InMemorySnapshotStore()

        func service(value: String) -> SnapshotService {
            let catalog = CapabilityCatalog(registry: StaticCapabilityRegistry(
                platform: .macOS,
                capabilities: [
                    FakeCapabilityFactory.make(
                        behaviour: .succeed(FakeSection(entities: [TestSchema.entity("one", value: .string(value))]))
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

        let a = try await service(value: "before").capture()
        clock.advance(by: 60)
        let later = service(value: "after")
        let b = try await later.capture()
        let viaService = try await later.diff(base: a.snapshot.id, target: b.snapshot.id)
        let direct = DiffEngine().diff(base: a.snapshot, target: b.snapshot)
        #expect(viaService.summary.totalChanges == direct.summary.totalChanges)
        #expect(viaService.changes.map(\.id) == direct.changes.map(\.id))
        let latest = try await later.latestDiff()
        #expect(latest?.changes.map(\.id) == viaService.changes.map(\.id))
    }

    @Test("Timeline of stored snapshots is pairwise")
    func serviceTimeline() async throws {
        let (service, clock) = makeService()
        try await service.capture()
        clock.advance(by: 120)
        try await service.capture()
        let timeline = try await service.timeline()
        #expect(timeline.steps.count == 1)
    }

    @Test("Capability enablement is recorded on the catalog")
    func capabilityToggle() async throws {
        let (service, _) = makeService()
        let statuses = await service.capabilityStatuses()
        let id = try #require(statuses.first?.metadata.id)
        await service.setCapabilityEnabled(false, for: id)
        let updated = await service.capabilityStatuses()
        #expect(updated.contains { $0.metadata.id == id && !$0.isEnabled })
    }
}

@Suite("File snapshot store")
struct FileSnapshotStoreTests {
    @Test("Save, load, query, annotate and delete round-trip on disk")
    func roundTrip() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)

        let first = SnapshotBuilder(id: "one", capturedAt: SnapshotBuilder.referenceDate)
            .labelled("First")
            .on(.macOS)
            .withWidgets([TestSchema.entity("a")])
            .build()
        let second = SnapshotBuilder(id: "two", capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(60))
            .on(.iOS)
            .withWidgets([TestSchema.entity("b")])
            .build()

        try await store.save(first)
        try await store.save(second)
        #expect(try await store.count() == 2)
        #expect(try await store.snapshot(id: first.id) == first)
        #expect(try await store.latest()?.id == second.id)

        let macs = try await store.summaries(matching: SnapshotQuery(platforms: [.macOS]))
        #expect(macs.map(\.id) == [first.id])

        try await store.annotate(id: first.id, with: SnapshotAnnotation(isPinned: true, tags: ["keep"]))
        let annotated = try await store.snapshot(id: first.id)
        #expect(annotated?.isPinned == true)
        #expect(annotated?.tags == ["keep"])

        #expect(try await store.storageSize() > 0)
        try await store.delete(id: first.id)
        #expect(try await store.count() == 1)
        try await store.deleteAll()
        #expect(try await store.count() == 0)
    }

    @Test("Saving the same id twice is an error")
    func duplicateSave() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let snapshot = SnapshotBuilder().withWidgets([TestSchema.entity("a")]).build()
        try await store.save(snapshot)
        await #expect(throws: StorageError.self) {
            try await store.save(snapshot)
        }
    }

    @Test("Deleting a missing snapshot is an error")
    func deleteMissing() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        await #expect(throws: StorageError.self) {
            try await store.delete(id: "missing")
        }
    }

    @Test("A corrupt snapshot file is skipped when listing")
    func corruptSkipped() async throws {
        let directory = TemporaryLibrary.make()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSnapshotStore(directory: directory)
        let good = SnapshotBuilder(id: "good").withWidgets([TestSchema.entity("a")]).build()
        try await store.save(good)

        let snapshotsDir = directory.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: snapshotsDir.appendingPathComponent("bad.json"))
        #expect(try await store.rebuildIndex() == 1)
        let listed = try await store.snapshots(matching: .all)
        #expect(listed.map(\.id) == [good.id])
    }

    @Test("StorageError descriptions are written for humans")
    func errorCopy() {
        #expect(StorageError.notFound("abc").errorDescription?.contains("not found") == true)
        #expect(StorageError.alreadyExists("abc").errorDescription?.contains("already exists") == true)
        #expect(StorageError.corrupted("x").errorDescription?.contains("unreadable") == true)
        #expect(StorageError.io("disk").errorDescription?.contains("disk") == true)
    }
}
