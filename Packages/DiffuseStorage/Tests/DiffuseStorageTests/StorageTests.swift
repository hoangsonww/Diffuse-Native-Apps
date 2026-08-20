import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot coding")
struct SnapshotCodingTests {
    @Test("Snapshots round-trip through the export envelope")
    func envelopeRoundTrip() throws {
        let snapshot = makeSnapshot()
        let decoded = try SnapshotCoding.decodeSnapshot(SnapshotCoding.encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Encoding is byte-stable across runs")
    func stableEncoding() throws {
        let snapshot = makeSnapshot()
        #expect(try SnapshotCoding.encode(snapshot) == SnapshotCoding.encode(snapshot))
    }

    @Test("A bare snapshot without an envelope still decodes")
    func bareSnapshotDecoding() throws {
        let snapshot = makeSnapshot()
        let encoder = SnapshotCoding.makeEncoder()
        let decoded = try SnapshotCoding.decodeSnapshot(encoder.encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Corrupt data throws rather than producing a broken snapshot")
    func corruptData() {
        #expect(throws: StorageError.self) {
            try SnapshotCoding.decodeSnapshot(Data("not json".utf8))
        }
    }

    @Test("A live Date survives encode then decode at millisecond resolution")
    func liveDateRoundTrip() throws {
        let snapshot = SnapshotBuilder(capturedAt: Date())
            .adding(TestSchema.section(entities: [
                TestSchema.entity("alpha", version: "1.0.0", size: 100),
            ]))
            .build()
        let decoded = try SnapshotCoding.decodeSnapshot(SnapshotCoding.encode(snapshot))
        #expect(decoded.capturedAt == snapshot.capturedAt)
        #expect(decoded == snapshot)
        #expect(SnapshotValidator.validate(snapshot).isEmpty)
    }

    @Test("Diffs round-trip too, so a comparison can be archived")
    func diffRoundTrip() throws {
        let diff = DiffFixtures.simple
        let decoded = try SnapshotCoding.decodeDiff(SnapshotCoding.encode(diff))
        #expect(decoded == diff)
    }

    private func makeSnapshot() -> Snapshot {
        SnapshotBuilder()
            .labelled("Test")
            .adding(TestSchema.section(entities: [
                TestSchema.entity("alpha", version: "1.0.0", size: 100),
                TestSchema.entity("beta", version: "2.0.0", size: 200),
            ]))
            .build()
    }
}

@Suite("Schema migration")
struct MigrationTests {
    @Test("The migration chain is complete and reaches the current version")
    func chainIsValid() {
        #expect(SnapshotMigrator.validateChain().isEmpty)
    }

    @Test("The current version migrates to itself without a migration")
    func currentVersionPassesThrough() throws {
        let snapshot = SnapshotBuilder().build()
        #expect(try SnapshotMigrator.migrate(snapshot, from: .current) == snapshot)
    }

    @Test("A snapshot from a newer build is refused rather than silently truncated")
    func futureVersionRefused() {
        let snapshot = SnapshotBuilder().build()
        #expect(throws: StorageError.self) {
            try SnapshotMigrator.migrate(snapshot, from: SchemaVersion(SchemaVersion.current.rawValue + 1))
        }
    }

    @Test("Support boundaries are reported honestly")
    func supportRange() {
        #expect(SnapshotMigrator.canMigrate(from: .v1))
        #expect(!SnapshotMigrator.canMigrate(from: SchemaVersion(0)))
        #expect(!SnapshotMigrator.canMigrate(from: SchemaVersion(99)))
    }
}

@Suite("In-memory store")
struct InMemoryStoreTests {
    @Test("Saving and reading back preserves the snapshot")
    func saveAndRead() async throws {
        let store = InMemorySnapshotStore()
        let snapshot = SnapshotBuilder().build()

        try await store.save(snapshot)
        #expect(try await store.snapshot(id: snapshot.id) == snapshot)
        #expect(try await store.count() == 1)
    }

    @Test("Snapshots are immutable: saving the same identifier twice fails")
    func immutability() async throws {
        let store = InMemorySnapshotStore()
        let snapshot = SnapshotBuilder().build()
        try await store.save(snapshot)

        await #expect(throws: StorageError.self) {
            try await store.save(snapshot)
        }
    }

    @Test("Annotations change labels without touching observed state")
    func annotation() async throws {
        let store = InMemorySnapshotStore()
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")]))
            .build()
        try await store.save(snapshot)

        try await store.annotate(id: snapshot.id, with: SnapshotAnnotation(label: "Before upgrade", isPinned: true))
        let updated = try await store.require(id: snapshot.id)

        #expect(updated.label == "Before upgrade")
        #expect(updated.isPinned)
        #expect(updated.sections == snapshot.sections, "Annotating must never alter what was observed")
    }

    @Test("The latest pair comes back oldest-first, ready for the diff engine")
    func latestPair() async throws {
        let store = InMemorySnapshotStore()
        let older = SnapshotBuilder(id: "older", capturedAt: SnapshotBuilder.referenceDate).build()
        let newer = SnapshotBuilder(id: "newer", capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(3600))
            .build()
        try await store.save(newer)
        try await store.save(older)

        let pair = try #require(await store.latestPair())
        #expect(pair.base.id == older.id)
        #expect(pair.target.id == newer.id)
    }

    @Test("Deleting a missing snapshot reports not found")
    func deleteMissing() async {
        let store = InMemorySnapshotStore()
        await #expect(throws: StorageError.self) {
            try await store.delete(id: "nope")
        }
    }
}

@Suite("Queries")
struct SnapshotQueryTests {
    private var summaries: [SnapshotSummary] {
        [
            makeSummary(id: "a", offset: 0, origin: .manual, pinned: true, tags: ["work"]),
            makeSummary(id: "b", offset: 3600, origin: .scheduled, tags: ["work", "home"]),
            makeSummary(id: "c", offset: 7200, origin: .imported, label: "From the iMac"),
            makeSummary(id: "d", offset: 86400 * 10, origin: .scheduled),
        ]
    }

    @Test("Newest-first is the default order")
    func defaultOrdering() {
        let result = SnapshotQuery.all.apply(to: summaries)
        #expect(result.map(\.id.rawValue) == ["d", "c", "b", "a"])
    }

    @Test("Oldest-first reverses the order")
    func oldestFirst() {
        let result = SnapshotQuery(sort: .oldestFirst).apply(to: summaries)
        #expect(result.map(\.id.rawValue) == ["a", "b", "c", "d"])
    }

    @Test("Limit and offset page stably")
    func paging() {
        let page = SnapshotQuery(limit: 2, offset: 1).apply(to: summaries)
        #expect(page.map(\.id.rawValue) == ["c", "b"])
    }

    @Test("Origin, tag and pin filters compose")
    func filtering() {
        #expect(SnapshotQuery(pinnedOnly: true).apply(to: summaries).map(\.id.rawValue) == ["a"])
        #expect(SnapshotQuery(origins: [.scheduled]).apply(to: summaries).count == 2)
        #expect(SnapshotQuery(tags: ["home"]).apply(to: summaries).map(\.id.rawValue) == ["b"])
    }

    @Test("Date range filtering is inclusive")
    func dateRange() {
        let start = SnapshotBuilder.referenceDate
        let query = SnapshotQuery(range: start ... start.addingTimeInterval(7200))
        #expect(query.apply(to: summaries).count == 3)
    }

    @Test("Search matches labels and device names")
    func searching() {
        #expect(SnapshotQuery(searchText: "imac").apply(to: summaries).map(\.id.rawValue) == ["c"])
        #expect(SnapshotQuery(searchText: "nothing here").apply(to: summaries).isEmpty)
    }

    private func makeSummary(
        id: String,
        offset: TimeInterval,
        origin: SnapshotOrigin,
        pinned: Bool = false,
        label: String? = nil,
        tags: Set<String> = []
    ) -> SnapshotSummary {
        SnapshotSummary(
            id: SnapshotID(id),
            capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(offset),
            platform: .macOS,
            origin: origin,
            label: label,
            isPinned: pinned,
            tags: tags,
            sectionCount: 1,
            entityCount: 1,
            deviceName: "Test Device",
            problemCount: 0
        )
    }
}

@Suite("File store")
struct FileStoreTests {
    @Test("Snapshots persist across store instances")
    func persistence() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")]))
            .build()

        let writer = FileSnapshotStore(directory: directory.url)
        try await writer.save(snapshot)

        let reader = FileSnapshotStore(directory: directory.url)
        #expect(try await reader.snapshot(id: snapshot.id) == snapshot)
        #expect(try await reader.count() == 1)
    }

    @Test("The index rebuilds from the snapshot files when it is deleted")
    func indexRebuild() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        for index in 0 ..< 3 {
            try await store.save(SnapshotBuilder(id: "snapshot-\(index)").identified("snapshot-\(index)").build())
        }

        try FileManager.default.removeItem(at: directory.url.appendingPathComponent("index.json"))

        let recovered = FileSnapshotStore(directory: directory.url)
        #expect(try await recovered.count() == 3, "The index is a cache, not the source of truth")
    }

    @Test("Storage size reflects what is on disk")
    func storageSize() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        #expect(try await store.storageSize() == 0)

        try await store.save(SnapshotBuilder().adding(TestSchema.section(entities: [TestSchema.entity("a")])).build())
        #expect(try await store.storageSize() > 0)
    }

    @Test("Deleting removes both the file and the index entry")
    func deletion() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        let snapshot = SnapshotBuilder().build()
        try await store.save(snapshot)
        try await store.delete(id: snapshot.id)

        #expect(try await store.count() == 0)
        #expect(try await store.snapshot(id: snapshot.id) == nil)
    }

    @Test("Deleting everything removes files and leaves an empty library")
    func deleteAll() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        try await store.save(SnapshotBuilder(id: "one").identified("one").build())
        try await store.save(SnapshotBuilder(id: "two").identified("two").build())
        try await store.deleteAll()

        #expect(try await store.count() == 0)
        let recovered = FileSnapshotStore(directory: directory.url)
        #expect(
            try await recovered.count() == 0,
            "An empty library must not resurrect deleted snapshots from leftover files"
        )
    }

    @Test("A corrupt snapshot file does not take down the rest of the library")
    func corruptFileIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        let good = SnapshotBuilder(id: "good").identified("good").build()
        try await store.save(good)

        let junk = directory.url
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("bad.json")
        try Data("{not a snapshot".utf8).write(to: junk)

        let loaded = try await store.snapshots(matching: .all)
        #expect(loaded.map(\.id) == [good.id])
    }

    @Test("A duplicate index entry is tolerated rather than crashing")
    func duplicateIndexKeys() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanUp() }

        let store = FileSnapshotStore(directory: directory.url)
        let snapshot = SnapshotBuilder(id: "dup").identified("dup").build()
        try await store.save(snapshot)

        let indexURL = directory.url.appendingPathComponent("index.json")
        let decoder = SnapshotCoding.makeDecoder()
        let stored = try decoder.decode([SnapshotSummary].self, from: Data(contentsOf: indexURL))
        try SnapshotCoding.makeEncoder().encode(stored + stored).write(to: indexURL)

        let recovered = FileSnapshotStore(directory: directory.url)
        #expect(try await recovered.count() == 1)
    }
}

@Suite("Retention")
struct RetentionTests {
    private let now = SnapshotBuilder.referenceDate

    @Test("Snapshots older than the window are removed")
    func ageBasedRemoval() {
        let summaries = (0 ..< 10).map { index in
            makeSummary(id: "s\(index)", daysAgo: index)
        }
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: RetentionPolicy(age: .days(5), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 1000
        )

        #expect(plan.deletions.count == 4)
        #expect(plan.reasons.values.allSatisfy { $0 == .tooOld })
    }

    @Test("Pinned and labelled snapshots survive retention")
    func protectedSnapshots() {
        let summaries = [
            makeSummary(id: "recent", daysAgo: 0),
            makeSummary(id: "pinned", daysAgo: 100, pinned: true),
            makeSummary(id: "labelled", daysAgo: 100, label: "Before the upgrade"),
            makeSummary(id: "ordinary", daysAgo: 100),
        ]
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 1000
        )

        #expect(plan.deletions.map(\.rawValue) == ["ordinary"])
    }

    @Test("The newest snapshot is never deleted, whatever the policy says")
    func newestIsAlwaysKept() {
        let summaries = (0 ..< 5).map { makeSummary(id: "s\($0)", daysAgo: 400 + $0) }
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: RetentionPolicy(age: .days(1), maximumBytes: 1, maximumCount: 0),
            now: now,
            averageBytesPerSnapshot: 1_000_000
        )

        #expect(!plan.deletions.contains(SnapshotID("s0")), "Deleting the newest leaves nothing to compare against")
        #expect(plan.retainedCount >= 1)
    }

    @Test("A count limit trims the oldest first")
    func countLimit() {
        let summaries = (0 ..< 10).map { makeSummary(id: "s\($0)", daysAgo: $0) }
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: 4),
            now: now,
            averageBytesPerSnapshot: 1000
        )

        #expect(plan.retainedCount == 4)
        #expect(plan.deletions.contains(SnapshotID("s9")))
        #expect(!plan.deletions.contains(SnapshotID("s0")))
    }

    @Test("An unlimited policy deletes nothing")
    func unlimitedPolicy() {
        let summaries = (0 ..< 50).map { makeSummary(id: "s\($0)", daysAgo: $0 * 30) }
        let plan = RetentionPlanner.plan(
            summaries: summaries,
            policy: .unlimited,
            now: now,
            averageBytesPerSnapshot: 1_000_000
        )
        #expect(plan.isEmpty)
    }

    @Test("Applying retention against a live store deletes exactly the plan")
    func appliedToStore() async throws {
        let store = InMemorySnapshotStore()
        for index in 0 ..< 6 {
            try await store.save(
                SnapshotBuilder(
                    id: "s\(index)",
                    capturedAt: now.addingTimeInterval(-Double(index) * 86400)
                ).build()
            )
        }

        let plan = try await store.applyRetention(
            RetentionPolicy(age: .days(3), maximumBytes: nil),
            now: now
        )

        // Snapshots 4 and 5 days old fall outside the window; the one exactly
        // three days old sits on the boundary and is kept.
        #expect(plan.deletions.count == 2)
        #expect(try await store.count() == 4)
    }

    private func makeSummary(
        id: String,
        daysAgo: Int,
        pinned: Bool = false,
        label: String? = nil
    ) -> SnapshotSummary {
        SnapshotSummary(
            id: SnapshotID(id),
            capturedAt: now.addingTimeInterval(-Double(daysAgo) * 86400),
            platform: .macOS,
            origin: .scheduled,
            label: label,
            isPinned: pinned,
            tags: [],
            sectionCount: 1,
            entityCount: 1,
            deviceName: "Test Device",
            problemCount: 0
        )
    }
}

@Suite("Validation")
struct ValidatorTests {
    @Test("A well-formed snapshot validates cleanly")
    func validSnapshot() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", version: "1.0.0", size: 10)]))
            .build()
        #expect(SnapshotValidator.validate(snapshot).isEmpty)
    }

    @Test("A property with no schema entry is reported")
    func undeclaredProperty() {
        var entity = TestSchema.entity("alpha")
        entity["mystery"] = .string("?")

        let snapshot = SnapshotBuilder().adding(TestSchema.section(entities: [entity])).build()
        let problems = SnapshotValidator.validate(snapshot)

        #expect(problems.contains { $0.contains("mystery") })
    }

    @Test("Duplicate identities within a section are reported")
    func duplicateIdentities() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha"), TestSchema.entity("alpha")]))
            .build()
        #expect(SnapshotValidator.validate(snapshot).contains { $0.contains("duplicate") })
    }

    @Test("A non-collecting section with entities is contradictory")
    func statusContradiction() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha")], status: .unavailable))
            .build()
        #expect(SnapshotValidator.validate(snapshot).contains { $0.contains("still has entities") })
    }
}

// MARK: - Helpers

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diffuse-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum DiffFixtures {
    static var simple: DiffResult {
        DiffResult(
            base: SnapshotBuilder(id: "base").build().reference,
            target: SnapshotBuilder(id: "target").build().reference,
            generatedAt: SnapshotBuilder.referenceDate,
            summary: .empty,
            sectionDiffs: [],
            clusters: []
        )
    }
}
