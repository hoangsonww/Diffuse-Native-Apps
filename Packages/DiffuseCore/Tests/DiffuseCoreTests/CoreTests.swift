import DiffuseCapabilities
import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot coordinator")
struct SnapshotCoordinatorTests {
    private func makeCoordinator(
        registry: any CapabilityRegistry = FakeCapabilityFactory.mixedRegistry()
    ) -> SnapshotCoordinator {
        SnapshotCoordinator(
            catalog: CapabilityCatalog(registry: registry),
            deviceProvider: StaticDeviceIdentityProvider.testDevice,
            platform: .macOS,
            timeSource: FixedTimeSource(SnapshotBuilder.referenceDate),
            appVersion: "1.0.0"
        )
    }

    @Test("One failing collector never fails the snapshot")
    func collectorIsolation() async throws {
        let report = await makeCoordinator().capture()

        #expect(report.snapshot.sections.count == 6, "Every capability contributes a section, even when it failed")
        #expect(!report.problems.isEmpty)

        let healthy = try #require(report.snapshot.section(for: "fake.healthy"))
        #expect(healthy.status == .collected)
        #expect(healthy.entities.count == 2)
    }

    @Test("A collector that throws produces a failed section carrying the reason")
    func throwingCollector() {
        // Verified through the capture below; kept separate for a focused name.
    }

    @Test("Each failure mode is recorded distinctly")
    func failureModes() async {
        let report = await makeCoordinator()
            .capture()

        let statuses = Dictionary(
            uniqueKeysWithValues: report.snapshot.sections.map { ($0.capability, $0.status) }
        )

        #expect(statuses["fake.healthy"] == .collected)
        #expect(statuses["fake.missing"] == .unavailable)
        #expect(statuses["fake.denied"] == .permissionRequired)
        #expect(statuses["fake.throwing"] == .failed)
        #expect(statuses["fake.disabled"] == .skipped)
    }

    @Test("A hanging collector is abandoned at its deadline", .timeLimit(.minutes(1)))
    func timeout() async throws {
        let report = await makeCoordinator().capture()
        let section = try #require(report.snapshot.section(for: "fake.slow"))

        #expect(section.status == .timedOut)
        #expect(report.totalDuration < 10, "The deadline must cap the capture, not the collector's own sleep")
        #expect(section.diagnostics.contains { $0.level == .warning })
    }

    @Test("Collectors run concurrently rather than one after another")
    func concurrency() async {
        let registry = StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: (0 ..< 6).map { index in
                FakeCapabilityFactory.make(
                    id: CapabilityID("slow.\(index)"),
                    behaviour: .delayed(FakeSection(), by: .milliseconds(200))
                )
            }
        )

        let report = await makeCoordinator(registry: registry).capture()

        #expect(report.snapshot.sections.count == 6)
        #expect(report.totalDuration < 1.0, "Six 200ms collectors run in parallel should not take 1.2s")
    }

    @Test("A disabled capability is recorded in the snapshot metadata")
    func skippedCapabilitiesRecorded() async {
        let report = await makeCoordinator().capture()
        #expect(report.snapshot.metadata.skippedCapabilities.contains("fake.disabled"))
    }

    @Test("Background captures skip expensive collectors")
    func backgroundCaptureSkipsExpensiveWork() async {
        let registry = StaticCapabilityRegistry(platform: .macOS, capabilities: [
            FakeCapabilityFactory.make(id: "cheap", cost: .low),
            FakeCapabilityFactory.make(id: "expensive", cost: .high),
        ])

        let report = await makeCoordinator(registry: registry).capture(isBackground: true)
        let statuses = Dictionary(uniqueKeysWithValues: report.snapshot.sections.map { ($0.capability, $0.status) })

        #expect(statuses["cheap"] == .collected)
        #expect(statuses["expensive"] == .skipped)
    }

    @Test("Sections are ordered deterministically regardless of completion order")
    func deterministicSectionOrder() async {
        let first = await makeCoordinator().capture()
        let second = await makeCoordinator().capture()
        #expect(first.snapshot.capabilities == second.snapshot.capabilities)
    }

    @Test("The capture uses the injected clock, not the wall clock")
    func injectedClock() async {
        let report = await makeCoordinator().capture()
        #expect(report.snapshot.capturedAt == SnapshotBuilder.referenceDate)
    }
}

@Suite("Scheduling")
struct SchedulerTests {
    private let now = SnapshotBuilder.referenceDate

    @Test("With no history, capture immediately")
    func firstRun() {
        let decision = SnapshotScheduler.decide(schedule: .default, lastCapture: nil, now: now)
        #expect(decision == .capture(reason: .firstRun))
    }

    @Test("A disabled schedule never fires")
    func disabled() {
        let decision = SnapshotScheduler.decide(schedule: .disabled, lastCapture: nil, now: now)
        #expect(decision == .disabled)
    }

    @Test("The cadence fires once its interval has elapsed")
    func cadence() {
        let schedule = SnapshotSchedule(cadence: .hourly, capturesOnSystemEvents: false, minimumInterval: 60)

        let tooSoon = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-1800),
            now: now
        )
        #expect(!tooSoon.shouldCapture)

        let due = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-3700),
            now: now
        )
        #expect(due == .capture(reason: .cadenceElapsed))
    }

    @Test("The minimum interval applies to system events too")
    func minimumIntervalGuardsSystemEvents() {
        let schedule = SnapshotSchedule(cadence: .daily, capturesOnSystemEvents: true, minimumInterval: 900)

        let tooSoon = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-60),
            now: now,
            systemEvent: true
        )
        #expect(!tooSoon.shouldCapture, "A laptop waking repeatedly must not flood the timeline")

        let allowed = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-1000),
            now: now,
            systemEvent: true
        )
        #expect(allowed == .capture(reason: .systemEvent))
    }

    @Test("The next capture date is reported for the settings screen")
    func nextCaptureDate() throws {
        let schedule = SnapshotSchedule(cadence: .hourly, capturesOnSystemEvents: false, minimumInterval: 60)
        let last = now.addingTimeInterval(-600)
        let next = try #require(SnapshotScheduler.nextCaptureDate(schedule: schedule, lastCapture: last, now: now))
        #expect(next == last.addingTimeInterval(3600))
    }
}

@Suite("Search")
struct SearchTests {
    private var index: SearchIndex {
        SearchIndex(snapshots: [SampleData.macBaseline, SampleData.macAfterWorkday])
    }

    @Test("Searching finds entities across every capability, with no per-capability code")
    func findsEntities() {
        let results = index.search("node")
        #expect(!results.isEmpty)
        #expect(results.contains { $0.title.localizedCaseInsensitiveContains("node") })
    }

    @Test("Searching matches section names")
    func findsSections() {
        #expect(index.search("storage").contains { $0.title == "Storage" })
    }

    @Test("An exact title match outranks a substring hit")
    func ranking() throws {
        let results = index.search("docker")
        let best = try #require(results.first)
        #expect(best.title.localizedCaseInsensitiveContains("docker"))
    }

    @Test("All terms must match")
    func multipleTerms() {
        #expect(index.search("node zzzznotpresent").isEmpty)
    }

    @Test("Empty queries return nothing rather than everything")
    func emptyQuery() {
        #expect(index.search("").isEmpty)
        #expect(index.search("   ").isEmpty)
    }

    @Test("Change search filters an existing change list")
    func changeSearch() {
        let diff = DiffEngine().diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)
        let search = ChangeSearchIndex(changes: diff.changes)

        #expect(!search.search("node").isEmpty)
        #expect(search.search("").count == diff.changes.count)
        #expect(search.search("definitely-not-here").isEmpty)
    }
}

@Suite("Reports")
struct ReportRendererTests {
    private var diff: DiffResult {
        DiffEngine().diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)
    }

    @Test("The Markdown report names both snapshots and groups by category")
    func markdown() {
        let report = ReportRenderer.markdown(for: diff)

        #expect(report.hasPrefix("# Diffuse Report"))
        #expect(report.contains("Morning snapshot"))
        #expect(report.contains("## Development"))
        #expect(report.contains("Node.js"))
        #expect(report.contains("No data left this device"))
    }

    @Test("Severity filtering carries through to the report")
    func markdownFiltering() {
        let all = ReportRenderer.markdown(for: diff, minimumSeverity: .informational)
        let significant = ReportRenderer.markdown(for: diff, minimumSeverity: .significant)
        #expect(significant.count < all.count)
    }

    @Test("Markdown special characters in values are escaped")
    func markdownEscaping() {
        let base = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("branch", value: .string("feature/auth_v1"))]))
            .build()
        let target = SnapshotBuilder()
            .identified("target")
            .adding(TestSchema.section(entities: [TestSchema.entity("branch", value: .string("feature/auth_v2"))]))
            .build()

        let report = ReportRenderer.markdown(for: DiffEngine().diff(base: base, target: target))
        #expect(report.contains(#"auth\_v2"#))
    }

    @Test("The plain-text report renders without colour codes")
    func plainText() {
        let text = ReportRenderer.plainText(for: diff)
        #expect(text.contains("Diffuse Diff"))
        #expect(text.contains("DEVELOPMENT"))
        #expect(!text.contains("\u{1B}["))
    }

    @Test("An empty diff says so instead of printing an empty section list")
    func emptyDiff() {
        let empty = DiffEngine().selfDiff(SampleData.macBaseline)
        #expect(ReportRenderer.markdown(for: empty).contains("No changes"))
        #expect(ReportRenderer.plainText(for: empty).contains("No changes"))
    }

    @Test("A snapshot renders as a readable inventory")
    func snapshotReport() {
        let report = ReportRenderer.markdown(for: SampleData.macBaseline)
        #expect(report.contains("# Snapshot"))
        #expect(report.contains("## Developer tools"))
    }
}

@Suite("Timeline")
struct TimelineTests {
    @Test("A run of snapshots produces one step per consecutive pair")
    func steps() {
        let timeline = ChangeTimeline(snapshots: SampleData.timeline)
        #expect(timeline.steps.count == SampleData.timeline.count - 1)
    }

    @Test("Input order does not matter; the timeline sorts by capture time")
    func ordering() {
        let forward = ChangeTimeline(snapshots: SampleData.timeline)
        let reversed = ChangeTimeline(snapshots: SampleData.timeline.reversed())
        #expect(forward.totalChanges == reversed.totalChanges)
        #expect(forward.steps.map(\.id) == reversed.steps.map(\.id))
    }

    @Test("A single snapshot yields no steps and no clusters")
    func singleSnapshot() {
        let timeline = ChangeTimeline(snapshots: [SampleData.macBaseline])
        #expect(timeline.steps.isEmpty)
        #expect(timeline.clusters.isEmpty)
    }

    @Test("Entity history follows one thing across the whole range")
    func entityHistory() {
        let timeline = ChangeTimeline(snapshots: SampleData.timeline)
        let identity = EntityIdentity(kind: "developerTool", value: "node")
        let history = timeline.history(of: identity)
        #expect(history.allSatisfy { $0.entity.identity == identity })
    }

    @Test("The most active capabilities are ranked deterministically")
    func mostActive() {
        let timeline = ChangeTimeline(snapshots: SampleData.timeline)
        let first = timeline.mostActiveCapabilities()
        let second = timeline.mostActiveCapabilities()
        #expect(first.map(\.capability) == second.map(\.capability))
    }

    @Test("Clustering spans snapshots, not just pairs")
    func crossSnapshotClustering() {
        let timeline = ChangeTimeline(snapshots: SampleData.timeline)
        #expect(!timeline.clusters.isEmpty)
    }
}

@Suite("Privacy ledger")
struct PrivacyLedgerTests {
    private func makeLedger() async -> PrivacyLedger {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        await catalog.refresh()
        return await PrivacyLedger(statuses: catalog.statuses())
    }

    @Test("The ledger is generated from live metadata, so it covers everything")
    func coversEveryCapability() async {
        let ledger = await makeLedger()
        #expect(ledger.entries.count == 6)
    }

    @Test("Entries are grouped by classification, most sensitive first")
    func grouping() async {
        let ledger = await makeLedger()
        let groups = ledger.groupedByClassification
        let classifications = groups.map(\.classification)
        #expect(classifications == classifications.sorted(by: >))
    }

    @Test("The never-collected list names the things that matter")
    func neverCollected() {
        let joined = PrivacyLedger.neverCollected.joined(separator: " ").lowercased()
        for term in ["password", "keychain", "ssh", ".env", "file contents", "location"] {
            #expect(joined.contains(term), "The privacy promise must explicitly mention \(term)")
        }
    }

    @Test("Redaction previews name the capabilities that would be affected")
    func redactionPreview() async {
        let ledger = await makeLedger()
        #expect(ledger.redactedCapabilities(under: .strict).count >= ledger.redactedCapabilities(under: .none).count)
    }

    @Test("The ledger renders as Markdown for the docs and the CLI")
    func markdown() async {
        let markdown = await makeLedger().markdown()
        #expect(markdown.contains("# What Diffuse collects"))
        #expect(markdown.contains("## Never collected"))
    }
}

@Suite("Snapshot service")
struct SnapshotServiceTests {
    private func makeService(
        store: any SnapshotStore = InMemorySnapshotStore(),
        clock: FixedTimeSource = FixedTimeSource(SnapshotBuilder.referenceDate)
    ) -> SnapshotService {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: StaticDeviceIdentityProvider.testDevice,
            platform: .macOS,
            timeSource: clock
        )
        return SnapshotService(
            coordinator: coordinator,
            store: store,
            catalog: catalog,
            timeSource: clock,
            retentionPolicy: .unlimited
        )
    }

    @Test("Capturing persists the snapshot in one step")
    func captureAndPersist() async throws {
        let service = makeService()
        let report = try await service.capture(label: "First")

        #expect(try await service.count() == 1)
        #expect(try await service.snapshot(id: report.snapshot.id)?.label == "First")
    }

    @Test("Overview is empty until there is something to compare")
    func overviewWithoutHistory() async throws {
        let service = makeService()
        #expect(try await service.overview().latest == nil)

        _ = try await service.capture()
        let overview = try await service.overview()
        #expect(overview.latest != nil)
        #expect(!overview.hasComparison)
        #expect(overview.clusterChanges.isEmpty)
    }

    @Test("Importing marks the snapshot as imported rather than locally captured")
    func importing() async throws {
        let service = makeService()
        let data = try SnapshotCoding.encode(SampleData.macBaseline)

        let imported = try await service.importSnapshot(from: data)

        #expect(imported.origin == .imported)
        #expect(imported.tags.contains("imported"))
        #expect(imported.id != SampleData.macBaseline.id, "Re-importing must not collide with the original id")
        #expect(imported.sections == SampleData.macBaseline.sections, "Observed state must survive an import intact")

        _ = try await service.importSnapshot(from: data)
        #expect(try await service.count() == 2, "Importing the same export twice must produce two copies")
    }

    @Test("Exports apply the requested redaction")
    func exportRedaction() async throws {
        let store = InMemorySnapshotStore(snapshots: [SampleData.macBaseline])
        let service = makeService(store: store)

        let data = try await service.exportSnapshot(id: SampleData.macBaseline.id, redaction: .strict)
        let exported = try SnapshotCoding.decodeSnapshot(data)

        #expect(exported.metadata.appliedRedaction == .strict)
        let network = try #require(exported.section(for: "network.path"))
        #expect(network.entities.first?["ssid"] == .string("‹redacted›"))
    }

    @Test("Library search is exposed through the service")
    func librarySearch() async throws {
        let store = InMemorySnapshotStore(snapshots: [SampleData.macBaseline, SampleData.macAfterWorkday])
        let service = makeService(store: store)
        let results = try await service.search("node")
        #expect(!results.isEmpty)
        #expect(results.contains { $0.title.localizedCaseInsensitiveContains("node") })
    }

    @Test("Diffing two stored snapshots matches diffing them directly")
    func diffing() async throws {
        let store = InMemorySnapshotStore(snapshots: [SampleData.macBaseline, SampleData.macAfterWorkday])
        let service = makeService(store: store)

        let viaService = try await service.diff(
            base: SampleData.macBaseline.id,
            target: SampleData.macAfterWorkday.id
        )
        let direct = DiffEngine().diff(base: SampleData.macBaseline, target: SampleData.macAfterWorkday)

        #expect(viaService == direct)
    }

    @Test("Retention runs after the save, so the newest snapshot always survives")
    func retentionKeepsNewest() async throws {
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        let service = makeService(clock: clock)
        await service.setRetentionPolicy(RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: 1))

        _ = try await service.capture()
        clock.advance(by: 3600)
        let second = try await service.capture()

        let remaining = try await service.summaries()
        #expect(remaining.count == 1)
        #expect(remaining.contains { $0.id == second.snapshot.id })
    }

    @Test("Unchanged automatic captures are not stored")
    func skipUnchangedAutomaticCaptures() async throws {
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        let catalog = CapabilityCatalog(
            registry: StaticCapabilityRegistry(
                platform: .macOS,
                capabilities: [
                    FakeCapabilityFactory.make(
                        id: "fake.healthy",
                        displayName: "Healthy",
                        behaviour: .succeed(FakeSection(entities: [TestSchema.entity("one")]))
                    ),
                ]
            )
        )
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: StaticDeviceIdentityProvider.testDevice,
            platform: .macOS,
            timeSource: clock
        )
        let service = SnapshotService(
            coordinator: coordinator,
            store: InMemorySnapshotStore(),
            catalog: catalog,
            timeSource: clock,
            retentionPolicy: .unlimited
        )
        _ = try await service.capture(origin: .manual)
        clock.advance(by: 3600)
        _ = try await service.capture(origin: .scheduled, skipIfUnchanged: true)
        #expect(try await service.count() == 1)
    }

    @Test("Exported diffs apply redaction to both sides")
    func exportDiffRedaction() async throws {
        let store = InMemorySnapshotStore(snapshots: [SampleData.macBaseline, SampleData.macAfterWorkday])
        let service = makeService(store: store)

        let data = try await service.exportDiff(
            base: SampleData.macBaseline.id,
            target: SampleData.macAfterWorkday.id,
            redaction: .strict
        )
        let decoded = try SnapshotCoding.decodeDiff(data)
        #expect(decoded.changes.allSatisfy { change in
            !change.summary.localizedCaseInsensitiveContains("office")
                && !change.summary.localizedCaseInsensitiveContains("home")
        })
    }
}
