import DiffuseCapabilities
import DiffuseCollectors
import DiffuseCore
import DiffuseDeveloperTools
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Golden fixtures")
struct GoldenFixtureTests {
    @Test("Fixture files exist so the suite is actually checking something")
    func fixturesArePresent() {
        #expect(FixtureLocator.exists, "Run Scripts/generate-fixtures.sh")
    }

    @Test(
        "Each snapshot fixture on disk matches the generator",
        arguments: FixtureGenerator.snapshots.map(\.name)
    )
    func snapshotFixturesMatch(name: String) throws {
        let url = FixtureLocator.snapshotURL(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "Missing fixture \(name)")

        let stored = try SnapshotCoding.decodeSnapshot(Data(contentsOf: url))
        let generated = try #require(FixtureGenerator.snapshot(named: name))

        #expect(stored == generated, "Fixture \(name) is stale. Run Scripts/generate-fixtures.sh and review the diff.")
    }

    @Test(
        "Each diff fixture matches what the engine produces today",
        arguments: FixtureGenerator.diffs.map(\.name)
    )
    func diffFixturesMatch(name: String) throws {
        let url = FixtureLocator.diffURL(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "Missing fixture \(name)")

        let stored = try SnapshotCoding.decodeDiff(Data(contentsOf: url))
        let generated = try #require(FixtureGenerator.expectedDiff(named: name))

        #expect(
            stored.summary.totalChanges == generated.summary.totalChanges,
            "Diff fixture \(name) changed: \(stored.summary.totalChanges) → \(generated.summary.totalChanges)"
        )
        #expect(stored.changes.map(\.id) == generated.changes.map(\.id), "Diff fixture \(name) is stale")
        #expect(stored == generated, "Diff fixture \(name) is stale")
    }

    @Test(
        "Every snapshot fixture is valid against the current schema",
        arguments: FixtureGenerator.snapshots.map(\.name)
    )
    func fixturesValidate(name: String) throws {
        let snapshot = try #require(FixtureGenerator.snapshot(named: name))
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.isEmpty, "\(name): \(problems.joined(separator: "; "))")
    }

    @Test("The workday fixture tells the story the product promises")
    func workdayDiffContent() throws {
        let diff = try #require(FixtureGenerator.expectedDiff(named: "mac-workday"))
        let summaries = diff.changes.map(\.summary).joined(separator: "\n").lowercased()

        #expect(summaries.contains("node.js 24.5.0 → 24.6.0"))
        #expect(summaries.contains("home → office"))
        #expect(summaries.contains("feature/auth → feature/webrtc"))
        #expect(summaries.contains("studio display removed"))
        #expect(summaries.contains("rust added"))
        #expect(diff.summary.significantCount >= 5)
    }

    @Test("Losing a permission is reported as a status change, not as data loss")
    func permissionLossFixture() throws {
        let diff = try #require(FixtureGenerator.expectedDiff(named: "mac-permission-loss"))
        let change = try #require(diff.changes.first { $0.capability == "network.path" })

        #expect(change.severity == .significant)
        #expect(change.property?.after == .string("Permission required"))
    }
}

@Suite("Capture to comparison")
struct EndToEndTests {
    @Test("A capture round-trips through storage, diffing and export")
    func fullPipeline() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diffuse-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let service = SnapshotService(
            coordinator: SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .macOS,
                timeSource: clock
            ),
            store: FileSnapshotStore(directory: directory),
            catalog: catalog,
            timeSource: clock,
            retentionPolicy: .unlimited
        )

        let first = try await service.capture(label: "Before")
        clock.advance(by: 3600)
        let second = try await service.capture(label: "After")

        #expect(try await service.count() == 2)

        let diff = try await service.diff(base: first.snapshot.id, target: second.snapshot.id)
        #expect(diff.summary.elapsed == 3600)

        let report = try await service.exportReport(base: first.snapshot.id, target: second.snapshot.id)
        #expect(report.contains("# Diffuse Report"))
        #expect(report.contains("Before"))

        let exported = try await service.exportSnapshot(id: second.snapshot.id)
        let reimported = try SnapshotCoding.decodeSnapshot(exported)
        #expect(reimported.id == second.snapshot.id)
    }

    @Test("A snapshot exported from one device imports into another")
    func crossDevicePortability() async throws {
        let sender = InMemorySnapshotStore(snapshots: [SampleData.macBaseline])
        let exported = try await sender.require(id: SampleData.macBaseline.id)
        let data = try SnapshotCoding.encode(exported.redacted(.standard))

        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let receiver = SnapshotService(
            coordinator: SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .iOS,
                timeSource: FixedTimeSource(SnapshotBuilder.referenceDate)
            ),
            store: InMemorySnapshotStore(),
            catalog: catalog
        )

        let imported = try await receiver.importSnapshot(from: data)

        #expect(imported.platform == .macOS, "An imported snapshot keeps the platform it was captured on")
        #expect(imported.origin == .imported)
        // The receiving build has none of the sending platform's collectors
        // compiled in, and can still render every section.
        #expect(imported.sections.count == SampleData.macBaseline.sections.count)
        #expect(imported.sections.allSatisfy { !$0.schema.entityKinds.isEmpty })
    }

    @Test("A snapshot from an unknown capability still diffs and renders")
    func unknownCapabilityIsUsable() throws {
        // Simulates a snapshot produced by a future build that knows about a
        // capability this build has never heard of. Because the schema travels
        // with the data, everything downstream still works.
        let futureSchema = SectionSchema(
            capability: "future.quantum",
            displayName: "Quantum coprocessor",
            summary: "Something this build has never heard of.",
            category: SectionCategory("quantum"),
            symbol: "atom",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "qubit",
                    singularName: "Qubit",
                    pluralName: "Qubits",
                    symbol: "atom",
                    additionSeverity: .significant,
                    removalSeverity: .critical,
                    properties: [
                        PropertyDescriptor(key: "coherence", displayName: "Coherence", unit: .percent,
                                           comparison: .numeric(tolerance: 0.01), severity: .critical, isPrimary: true),
                    ]
                ),
            ]
        )

        func section(coherence: Double) -> SnapshotSection {
            SnapshotSection(
                capability: "future.quantum",
                collector: "future.collector",
                collectorVersion: "9.0.0",
                collectedAt: SnapshotBuilder.referenceDate,
                status: .collected,
                schema: futureSchema,
                entities: [
                    SnapshotEntity(kind: "qubit", id: "q0", displayName: "Qubit 0",
                                   properties: ["coherence": .percentage(coherence)]),
                ]
            )
        }

        let base = SnapshotBuilder(id: "future-base").adding(section(coherence: 0.99)).build()
        let target = SnapshotBuilder(id: "future-target").adding(section(coherence: 0.62)).build()

        let diff = DiffEngine().diff(base: base, target: target)
        let change = try #require(diff.changes.first)

        #expect(change.severity == .critical, "Severity comes from the travelling schema, not from local knowledge")
        #expect(change.summary == "Qubit 0 62% → 99%" || change.summary == "Qubit 0 99% → 62%")
        #expect(change.category.displayName == "Quantum")

        // And it survives a full serialization round trip.
        let decoded = try SnapshotCoding.decodeSnapshot(SnapshotCoding.encode(target))
        #expect(decoded == target)
        #expect(SnapshotValidator.validate(decoded).isEmpty)
    }

    @Test("A live capture on this machine produces a valid snapshot", .timeLimit(.minutes(2)))
    func liveCaptureIsValid() async {
        #if os(macOS)
        let registry = MacCapabilityRegistry()
        #else
        let registry = StaticCapabilityRegistry(
            platform: Platform.current,
            capabilities: [SystemInfoCollector.capability(platforms: [Platform.current])]
        )
        #endif

        let catalog = CapabilityCatalog(registry: registry)
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: "integration-test"),
            platform: Platform.current
        )

        let report = await coordinator.capture()
        let problems = SnapshotValidator.validate(report.snapshot)

        #expect(problems.isEmpty, "\(problems.joined(separator: "; "))")
        #expect(!report.snapshot.sections.isEmpty)
        #expect(report.snapshot.section(for: "system.info")?.status == .collected)
    }

    @Test("Two live captures diff without spurious changes", .timeLimit(.minutes(2)))
    func liveCaptureStability() async {
        #if os(macOS)
        // Only cheap, stable capabilities: this test asserts that a
        // snapshot taken twice in a row is quiet, which would be
        // meaningless if it included battery level or free space.
        let registry = StaticCapabilityRegistry(platform: .macOS, capabilities: [
            SystemInfoCollector.capability(platforms: [.macOS]),
            MacHardwareCollector.capability,
            MacDisplayCollector.capability,
        ])
        #else
        let registry = StaticCapabilityRegistry(
            platform: Platform.current,
            capabilities: [SystemInfoCollector.capability(platforms: [Platform.current])]
        )
        #endif

        let catalog = CapabilityCatalog(registry: registry)
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: "integration-test"),
            platform: Platform.current
        )

        let first = await coordinator.capture()
        let second = await coordinator.capture()

        let diff = DiffEngine().diff(base: first.snapshot, target: second.snapshot)
        #expect(
            diff.isEmpty,
            "Stable state must not drift between back-to-back captures: \(diff.changes.map(\.summary))"
        )
    }
}

/// The architectural test the whole design is aimed at.
///
/// If adding a capability required touching the diff engine, storage, search,
/// export or the apps, the extensibility claim would be false. This suite adds
/// a capability that nothing else has ever heard of, and asserts that every
/// downstream system handles it with no modification.
@Suite("Adding a capability is a localized change")
struct ExtensibilityTests {
    private static let capability = CapabilityID("test.rust-toolchain")

    private static var schema: SectionSchema {
        SectionSchema(
            capability: capability,
            displayName: "Rust toolchain",
            summary: "Installed Rust toolchains.",
            category: .development,
            symbol: "gearshape.2",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "rustToolchain",
                    singularName: "Toolchain",
                    pluralName: "Toolchains",
                    symbol: "gearshape.2",
                    additionSeverity: .significant,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(key: "version", displayName: "Version", unit: .version,
                                           severity: .significant, isPrimary: true),
                        PropertyDescriptor(key: "channel", displayName: "Channel", severity: .notable),
                    ]
                ),
            ],
            attributes: [
                PropertyDescriptor(key: "toolchainCount", displayName: "Toolchains", unit: .count, severity: .notable),
            ]
        )
    }

    private struct RustSection: CollectedSection {
        let version: String
        let channel: String

        static var schema: SectionSchema {
            ExtensibilityTests.schema
        }

        var entities: [SnapshotEntity] {
            [
                SnapshotEntity(
                    kind: "rustToolchain",
                    id: "stable",
                    displayName: "Rust",
                    subtitle: version,
                    properties: [
                        "version": .version(SemanticVersion(version) ?? "0.0.0"),
                        "channel": .string(channel),
                    ]
                ),
            ]
        }

        var attributes: [PropertyKey: PropertyValue] {
            ["toolchainCount": .integer(1)]
        }
    }

    private struct RustCollector: SnapshotCollector {
        let identifier: CollectorID = "test.rust"
        let version: String
        func collect(context _: CollectionContext) async throws -> RustSection {
            RustSection(version: version, channel: "stable")
        }
    }

    private static func makeCapability(version: String) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                RustSection.self,
                summary: "Rust toolchains.",
                collectionDescription: "Runs rustc --version and records the toolchain version and channel.",
                platforms: [.macOS]
            ),
            collector: { RustCollector(version: version) }
        ).erased
    }

    private static func snapshot(id _: String, version: String) async throws -> Snapshot {
        let registry = StaticCapabilityRegistry(platform: .macOS, capabilities: [makeCapability(version: version)])
        let catalog = CapabilityCatalog(registry: registry)
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: StaticDeviceIdentityProvider.testDevice,
            platform: .macOS,
            timeSource: FixedTimeSource(SnapshotBuilder.referenceDate)
        )
        return await coordinator.capture().snapshot
    }

    @Test("The coordinator collects it with no registration beyond the registry")
    func coordinatorHandlesIt() async throws {
        let snapshot = try await Self.snapshot(id: "rust", version: "1.81.0")
        let section = try #require(snapshot.section(for: Self.capability))

        #expect(section.status == .collected)
        #expect(section.entities.count == 1)
        #expect(section.attributes["toolchainCount"] == .integer(1))
    }

    @Test("The validator accepts it because the schema describes it")
    func validatorHandlesIt() async throws {
        let snapshot = try await Self.snapshot(id: "rust", version: "1.81.0")
        #expect(SnapshotValidator.validate(snapshot).isEmpty)
    }

    @Test("Storage persists and restores it unchanged")
    func storageHandlesIt() async throws {
        let snapshot = try await Self.snapshot(id: "rust", version: "1.81.0")
        let store = InMemorySnapshotStore()
        try await store.save(snapshot)
        #expect(try await store.snapshot(id: snapshot.id) == snapshot)
    }

    @Test("The diff engine compares it, applying the schema's severity rules")
    func diffEngineHandlesIt() async throws {
        let before = try await Self.snapshot(id: "before", version: "1.81.0")
        let after = try await Self.snapshot(id: "after", version: "2.0.0")

        let diff = DiffEngine().diff(base: before, target: after)
        let change = try #require(diff.changes.first { $0.property?.key == "version" })

        #expect(change.severity == .critical, "Declared significant, escalated by the major version jump")
        #expect(change.summary == "Rust 1.81.0 → 2.0.0")
    }

    @Test("Search indexes it without knowing what Rust is")
    func searchHandlesIt() async throws {
        let snapshot = try await Self.snapshot(id: "rust", version: "1.81.0")
        let results = SearchIndex(snapshots: [snapshot]).search("rust")
        #expect(!results.isEmpty)
    }

    @Test("Export renders it in Markdown with no new template")
    func exportHandlesIt() async throws {
        let before = try await Self.snapshot(id: "before", version: "1.81.0")
        let after = try await Self.snapshot(id: "after", version: "1.82.0")

        let report = ReportRenderer.markdown(for: DiffEngine().diff(base: before, target: after))
        #expect(report.contains("## Development"))
        #expect(report.contains("Rust"))
    }

    @Test("The privacy ledger documents it automatically")
    func privacyLedgerHandlesIt() async throws {
        let registry = StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [Self.makeCapability(version: "1.81.0")]
        )
        let catalog = CapabilityCatalog(registry: registry)
        await catalog.refresh()

        let ledger = await PrivacyLedger(statuses: catalog.statuses())
        let entry = try #require(ledger.entries.first { $0.capability == Self.capability })

        #expect(entry.collectionDescription.contains("rustc --version"))
        #expect(ledger.markdown().contains("Rust toolchain"))
    }

    @Test("The timeline tracks its history over many snapshots")
    func timelineHandlesIt() async {
        let versions = ["1.79.0", "1.80.0", "1.81.0"]
        var snapshots: [Snapshot] = []

        for (index, version) in versions.enumerated() {
            let registry = StaticCapabilityRegistry(
                platform: .macOS,
                capabilities: [Self.makeCapability(version: version)]
            )
            let catalog = CapabilityCatalog(registry: registry)
            let clock = FixedTimeSource(SnapshotBuilder.referenceDate.addingTimeInterval(Double(index) * 86400))
            let coordinator = SnapshotCoordinator(
                catalog: catalog,
                deviceProvider: StaticDeviceIdentityProvider.testDevice,
                platform: .macOS,
                timeSource: clock
            )
            await snapshots.append(coordinator.capture().snapshot)
        }

        let timeline = ChangeTimeline(snapshots: snapshots)
        let history = timeline.history(of: EntityIdentity(kind: "rustToolchain", value: "stable"))

        #expect(history.count == 2, "Two upgrades across three snapshots")
        #expect(timeline.mostActiveCapabilities().first?.capability == Self.capability)
    }
}
