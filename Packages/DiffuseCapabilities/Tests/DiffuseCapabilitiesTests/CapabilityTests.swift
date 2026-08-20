import DiffuseCapabilities
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Availability")
struct AvailabilityTests {
    @Test("Only available capabilities report as available")
    func availabilityFlags() {
        #expect(CapabilityAvailability.available.isAvailable)
        #expect(!CapabilityAvailability.unavailable(reason: "gone").isAvailable)
        #expect(!CapabilityAvailability.unsupported(reason: "never").isAvailable)
    }

    @Test("Unsupported capabilities are hidden from the UI, unavailable ones are not")
    func discoverability() {
        #expect(CapabilityAvailability.available.isDiscoverable)
        #expect(CapabilityAvailability.unavailable(reason: "not installed").isDiscoverable)
        #expect(!CapabilityAvailability.unsupported(reason: "no such API here").isDiscoverable)
    }

    @Test("Only some states are worth retrying without user action")
    func retryability() {
        #expect(CapabilityAvailability.temporarilyUnavailable(reason: "asleep").isRetryable)
        #expect(CapabilityAvailability.unavailable(reason: "not installed").isRetryable)
        #expect(!CapabilityAvailability.unsupported(reason: "no").isRetryable)
        #expect(!CapabilityAvailability.permissionRequired(Self.permission).isRetryable)
    }

    @Test("Each availability maps to the status a section should record")
    func statusMapping() {
        #expect(CapabilityAvailability.available.collectionStatus == .collected)
        #expect(CapabilityAvailability.unsupported(reason: "x").collectionStatus == .unsupported)
        #expect(CapabilityAvailability.permissionRequired(Self.permission).collectionStatus == .permissionRequired)
    }

    @Test("Availability survives Codable, including its permission payload")
    func codable() throws {
        let values: [CapabilityAvailability] = [
            .available,
            .unavailable(reason: "not installed"),
            .unsupported(reason: "no API"),
            .permissionRequired(Self.permission),
            .temporarilyUnavailable(reason: "daemon down"),
        ]

        for value in values {
            let decoded = try JSONDecoder().decode(
                CapabilityAvailability.self,
                from: JSONEncoder().encode(value)
            )
            #expect(decoded == value)
        }
    }

    private static let permission = PermissionRequirement(
        id: "test.permission",
        displayName: "Test access",
        rationale: "Because the test says so."
    )
}

@Suite("Registry")
struct RegistryTests {
    @Test("Registration order never influences the capability list")
    func orderIndependence() {
        let a = FakeCapabilityFactory.make(id: "z.last")
        let b = FakeCapabilityFactory.make(id: "a.first")

        let forward = StaticCapabilityRegistry(platform: .macOS, capabilities: [a, b])
        let backward = StaticCapabilityRegistry(platform: .macOS, capabilities: [b, a])

        #expect(forward.capabilityIDs == backward.capabilityIDs)
        #expect(forward.capabilityIDs == ["a.first", "z.last"])
    }

    @Test("Combining registries lets later entries win")
    func combining() {
        let base = StaticCapabilityRegistry(platform: .macOS, capabilities: [
            FakeCapabilityFactory.make(id: "shared", displayName: "Original"),
        ])
        let override = StaticCapabilityRegistry(platform: .macOS, capabilities: [
            FakeCapabilityFactory.make(id: "shared", displayName: "Replacement"),
        ])

        let merged = StaticCapabilityRegistry.combining(platform: .macOS, [base, override])
        #expect(merged.capabilities.count == 1)
        #expect(merged.capability(with: "shared")?.metadata.displayName == "Replacement")
    }

    @Test("Grouping by category is stable and ordered")
    func grouping() {
        let registry = FakeCapabilityFactory.mixedRegistry()
        let groups = registry.groupedByCategory
        #expect(groups.count == 1)
        #expect(groups.first?.capabilities.count == 6)
    }
}

@Suite("Catalog")
struct CatalogTests {
    @Test("Refreshing probes every capability")
    func refresh() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let statuses = await catalog.refresh()

        #expect(statuses.count == 6)
        #expect(statuses.count { $0.availability.isAvailable } == 4)
    }

    @Test("Statuses before a refresh admit they are unknown rather than guessing")
    func unprobedStatuses() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        let statuses = await catalog.statuses()
        #expect(statuses.allSatisfy { !$0.availability.isAvailable })
    }

    @Test("Capabilities disabled by default start switched off")
    func defaultEnablement() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        #expect(await catalog.isEnabled("fake.healthy"))
        #expect(await !(catalog.isEnabled("fake.disabled")))
    }

    @Test("The collection plan assigns each capability the right role")
    func collectionPlan() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        await catalog.refresh()
        let plan = await catalog.collectionPlan()

        let byID = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.decision) })

        #expect(byID["fake.healthy"] == .collect)
        #expect(byID["fake.missing"] == .placeholder(.unavailable))
        #expect(byID["fake.denied"] == .placeholder(.permissionRequired))
        #expect(byID["fake.disabled"] == .skipped)
    }

    @Test("A cost ceiling excludes expensive capabilities")
    func costCeiling() async {
        let registry = StaticCapabilityRegistry(platform: .macOS, capabilities: [
            FakeCapabilityFactory.make(id: "cheap", cost: .low),
            FakeCapabilityFactory.make(id: "expensive", cost: .high),
        ])
        let catalog = CapabilityCatalog(registry: registry)
        await catalog.refresh()

        let plan = await catalog.collectionPlan(maximumCost: .low)
        let byID = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0.decision) })

        #expect(byID["cheap"] == .collect)
        #expect(byID["expensive"] == .skipped)
    }

    @Test("Toggling a capability changes whether it will collect")
    func toggling() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        await catalog.refresh()

        await catalog.setEnabled(false, for: "fake.healthy")
        let status = await catalog.status(for: "fake.healthy")
        #expect(status?.willCollect == false)

        await catalog.setEnabled(true, for: "fake.healthy")
        #expect(await catalog.status(for: "fake.healthy")?.willCollect == true)
    }

    @Test("Enablement persists across catalog instances and keeps new defaults on")
    func enablementPersistence() async {
        let store = InMemoryEnablementStore()
        let catalog = CapabilityCatalog(
            registry: FakeCapabilityFactory.mixedRegistry(),
            enablementStore: store
        )

        await catalog.setEnabled(false, for: "fake.healthy")
        await catalog.setEnabled(true, for: "fake.disabled")

        let restored = CapabilityCatalog(
            registry: FakeCapabilityFactory.mixedRegistry(),
            enablementStore: store
        )
        #expect(await !restored.isEnabled("fake.healthy"))
        #expect(await restored.isEnabled("fake.disabled"))

        let extra = FakeCapabilityFactory.make(id: "fake.brand-new")
        let expanded = StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: FakeCapabilityFactory.mixedRegistry().capabilities + [extra]
        )
        let upgraded = CapabilityCatalog(registry: expanded, enablementStore: store)
        #expect(await upgraded.isEnabled("fake.brand-new"), "A new default-on capability must not inherit 'off'")
        #expect(await !upgraded.isEnabled("fake.healthy"))
    }

    @Test("Resolved enablement treats a missing store as the registry defaults")
    func resolvedEnablementDefaults() {
        let registry = FakeCapabilityFactory.mixedRegistry()
        let enabled = CapabilityCatalog.resolvedEnablement(registry: registry, stored: nil)
        #expect(enabled.contains("fake.healthy"))
        #expect(!enabled.contains("fake.disabled"))
    }

    @Test("Costs order from cheap to expensive with sensible timeouts")
    func costOrdering() {
        #expect(CollectionCost.low < CollectionCost.moderate)
        #expect(CollectionCost.moderate < CollectionCost.high)
        #expect(CollectionCost.low.defaultTimeout < CollectionCost.high.defaultTimeout)
    }
}

@Suite("Type erasure")
struct AnyCapabilityTests {
    @Test("A typed collector output projects into a generic section")
    func projection() async throws {
        let capability = FakeCapabilityFactory.make(
            id: "projection.test",
            behaviour: .succeed(FakeSection(
                entities: [TestSchema.entity("alpha"), TestSchema.entity("beta")],
                attributes: ["total": .integer(2)]
            ))
        )

        let section = try await capability.collect(
            context: CollectionContext(startedAt: SnapshotBuilder.referenceDate, platform: .macOS)
        )

        #expect(section.capability == "projection.test")
        #expect(section.entities.count == 2)
        #expect(section.attributes["total"] == .integer(2))
        #expect(section.status == .collected)
        #expect(section.duration >= 0)
    }

    @Test("A collector error propagates for the coordinator to record")
    func errorPropagation() async {
        let capability = FakeCapabilityFactory.make(behaviour: .fail(.permissionDenied("nope")))

        await #expect(throws: CollectorError.self) {
            try await capability.collect(
                context: CollectionContext(startedAt: SnapshotBuilder.referenceDate, platform: .macOS)
            )
        }
    }

    @Test("Placeholders record why nothing was collected")
    func placeholders() {
        let capability = FakeCapabilityFactory.make(id: "placeholder.test")
        let section = capability.placeholder(
            status: .timedOut,
            at: SnapshotBuilder.referenceDate,
            diagnostics: [.warning("Took too long")]
        )

        #expect(section.status == .timedOut)
        #expect(section.entities.isEmpty)
        #expect(section.diagnostics.count == 1)
        #expect(section.schema.capability == "placeholder.test")
    }

    @Test("Errors map to the status a section should carry")
    func errorStatusMapping() {
        #expect(CollectorError.unavailable("x").status == .unavailable)
        #expect(CollectorError.permissionDenied("x").status == .permissionRequired)
        #expect(CollectorError.timedOut.status == .timedOut)
        #expect(CollectorError.malformedOutput("x").status == .failed)
    }
}

@Suite("Environment doubles")
struct EnvironmentTests {
    @Test("The fake clock only moves when a test says so")
    func fixedClock() {
        let clock = FixedTimeSource(SnapshotBuilder.referenceDate)
        #expect(clock.now == SnapshotBuilder.referenceDate)

        clock.advance(by: 3600)
        #expect(clock.now == SnapshotBuilder.referenceDate.addingTimeInterval(3600))
    }

    @Test("The fake filesystem answers existence and directory listing")
    func fakeFileSystem() throws {
        let fileSystem = FakeFileSystem(
            textFiles: [
                "/Applications/Thing.app/Contents/Info.plist": "<plist/>",
                "/Applications/Other.app/Contents/Info.plist": "<plist/>",
            ],
            directories: ["/Applications"]
        )

        #expect(fileSystem.isDirectory(at: "/Applications"))
        #expect(fileSystem.fileExists(at: "/Applications/Thing.app/Contents/Info.plist"))
        #expect(try fileSystem.contentsOfDirectory(at: "/Applications") == ["Other.app", "Thing.app"])
    }

    @Test("Reading is capped at the requested byte count")
    func readCapping() throws {
        let fileSystem = FakeFileSystem(textFiles: ["/a.txt": "abcdefghij"])
        #expect(try fileSystem.readFile(at: "/a.txt", maximumBytes: 4).count == 4)
    }

    @Test("Missing paths throw rather than returning empty data")
    func missingPaths() {
        let fileSystem = FakeFileSystem()
        #expect(throws: CollectorError.self) {
            try fileSystem.readFile(at: "/nope", maximumBytes: 10)
        }
    }
}
