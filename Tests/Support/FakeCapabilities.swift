import DiffuseCapabilities
import DiffuseModels
import Foundation

/// A collected section whose contents a test dictates entirely.
public struct FakeSection: CollectedSection {
    public let entities: [SnapshotEntity]
    public let attributes: [PropertyKey: PropertyValue]
    public let diagnostics: [Diagnostic]
    public let status: CollectionStatus

    public init(
        entities: [SnapshotEntity] = [],
        attributes: [PropertyKey: PropertyValue] = [:],
        diagnostics: [Diagnostic] = [],
        status: CollectionStatus = .collected
    ) {
        self.entities = entities
        self.attributes = attributes
        self.diagnostics = diagnostics
        self.status = status
    }

    public static let schema = TestSchema.make()
}

/// A collector whose behaviour — succeed, throw, or hang — a test chooses.
///
/// Hanging is the interesting one: it is how the coordinator's per-collector
/// deadline gets exercised without waiting on a real subprocess.
public struct FakeCollector: SnapshotCollector {
    public enum Behaviour: Sendable {
        case succeed(FakeSection)
        case fail(CollectorError)
        case hang(for: Duration)
        case delayed(FakeSection, by: Duration)
    }

    public let identifier: CollectorID
    public let version: SemanticVersion
    private let behaviour: Behaviour

    public init(identifier: CollectorID = "fake.collector", version: SemanticVersion = "1.0.0", behaviour: Behaviour) {
        self.identifier = identifier
        self.version = version
        self.behaviour = behaviour
    }

    public func collect(context _: CollectionContext) async throws -> FakeSection {
        switch behaviour {
        case let .succeed(section):
            return section
        case let .fail(error):
            throw error
        case let .hang(duration):
            try await Task.sleep(for: duration)
            return FakeSection()
        case let .delayed(section, duration):
            try await Task.sleep(for: duration)
            return section
        }
    }
}

/// Builds a capability around a `FakeCollector`, with a chosen availability.
public enum FakeCapabilityFactory {
    public static func make(
        id: CapabilityID = TestSchema.capability,
        displayName: String = "Widgets",
        availability: CapabilityAvailability = .available,
        cost: CollectionCost = .low,
        isEnabledByDefault: Bool = true,
        behaviour: FakeCollector.Behaviour = .succeed(FakeSection())
    ) -> AnyCapability {
        var schema = TestSchema.make()
        schema = SectionSchema(
            capability: id,
            displayName: displayName,
            summary: schema.summary,
            category: schema.category,
            symbol: schema.symbol,
            privacy: schema.privacy,
            entityKinds: schema.entityKinds,
            attributes: schema.attributes
        )

        let metadata = CapabilityMetadata(
            id: id,
            displayName: displayName,
            summary: "A fake capability for tests.",
            collectionDescription: "Collects nothing real.",
            category: schema.category,
            symbol: schema.symbol,
            privacy: schema.privacy,
            platforms: [.macOS, .iOS, .iPadOS, .watchOS],
            schema: schema,
            isEnabledByDefault: isEnabledByDefault,
            cost: cost
        )

        return AnyCapability(
            BasicCapability(
                metadata: metadata,
                availability: { availability },
                collector: { FakeCollector(identifier: CollectorID("\(id.rawValue).fake"), behaviour: behaviour) }
            )
        )
    }

    /// A registry of capabilities covering every availability state, used to
    /// verify that the coordinator records each one correctly.
    public static func mixedRegistry() -> StaticCapabilityRegistry {
        StaticCapabilityRegistry(
            platform: .macOS,
            capabilities: [
                make(id: "fake.healthy", displayName: "Healthy", behaviour: .succeed(
                    FakeSection(entities: [TestSchema.entity("one"), TestSchema.entity("two")])
                )),
                make(id: "fake.missing", displayName: "Missing", availability: .unavailable(reason: "Not installed")),
                make(
                    id: "fake.denied",
                    displayName: "Denied",
                    availability: .permissionRequired(
                        PermissionRequirement(id: "test.permission", displayName: "Test access", rationale: "Because.")
                    )
                ),
                make(id: "fake.throwing", displayName: "Throwing", behaviour: .fail(.malformedOutput("bad output"))),
                make(id: "fake.slow", displayName: "Slow", cost: .low, behaviour: .hang(for: .seconds(30))),
                make(id: "fake.disabled", displayName: "Disabled", isEnabledByDefault: false),
            ]
        )
    }
}
