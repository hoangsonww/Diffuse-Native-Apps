import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import Foundation

/// Locates the repository's checked-in fixtures.
///
/// Resolved from `#filePath` rather than a resource bundle so the same
/// fixtures are readable from unit tests, integration tests and the CLI
/// without three copies of the files.
public enum FixtureLocator {
    public static let repositoryRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        // Tests/Support/TestSupport.swift → repository root
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    public static var fixturesDirectory: URL {
        repositoryRoot.appendingPathComponent("Fixtures", isDirectory: true)
    }

    public static func snapshotURL(_ name: String) -> URL {
        fixturesDirectory
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }

    public static func diffURL(_ name: String) -> URL {
        fixturesDirectory
            .appendingPathComponent("diffs", isDirectory: true)
            .appendingPathComponent("\(name).expected.json")
    }

    public static func data(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public static var exists: Bool {
        FileManager.default.fileExists(atPath: fixturesDirectory.path)
    }
}

/// Builds snapshots for tests without repeating boilerplate.
///
/// Every value defaults to something fixed, so a test only has to state the
/// part it cares about and the rest stays deterministic.
public struct SnapshotBuilder {
    public static let referenceDate = Date(timeIntervalSince1970: 1_787_130_240)

    private var id: SnapshotID
    private var capturedAt: Date
    private var platform: Platform
    private var sections: [SnapshotSection]
    private var origin: SnapshotOrigin
    private var label: String?
    private var isPinned: Bool
    private var tags: Set<String>
    private var deviceName: String

    public init(
        id: String = "test-snapshot",
        capturedAt: Date = SnapshotBuilder.referenceDate,
        platform: Platform = .macOS,
        origin: SnapshotOrigin = .synthetic
    ) {
        self.id = SnapshotID(id)
        self.capturedAt = capturedAt
        self.platform = platform
        self.origin = origin
        sections = []
        isPinned = false
        tags = []
        deviceName = "Test Device"
    }

    public func labelled(_ label: String) -> SnapshotBuilder {
        var copy = self
        copy.label = label
        return copy
    }

    public func at(_ date: Date) -> SnapshotBuilder {
        var copy = self
        copy.capturedAt = date
        return copy
    }

    public func identified(_ id: String) -> SnapshotBuilder {
        var copy = self
        copy.id = SnapshotID(id)
        return copy
    }

    public func on(_ platform: Platform) -> SnapshotBuilder {
        var copy = self
        copy.platform = platform
        return copy
    }

    public func originating(_ origin: SnapshotOrigin) -> SnapshotBuilder {
        var copy = self
        copy.origin = origin
        return copy
    }

    public func pinned(_ isPinned: Bool = true) -> SnapshotBuilder {
        var copy = self
        copy.isPinned = isPinned
        return copy
    }

    public func tagged(_ tags: Set<String>) -> SnapshotBuilder {
        var copy = self
        copy.tags = tags
        return copy
    }

    public func named(_ deviceName: String) -> SnapshotBuilder {
        var copy = self
        copy.deviceName = deviceName
        return copy
    }

    public func adding(_ section: SnapshotSection) -> SnapshotBuilder {
        var copy = self
        copy.sections.append(section)
        return copy
    }

    public func withWidgets(_ entities: [SnapshotEntity], schema: SectionSchema? = nil) -> SnapshotBuilder {
        adding(TestSchema.section(entities: entities, at: capturedAt, schema: schema))
    }

    public func build() -> Snapshot {
        Snapshot(
            id: id,
            capturedAt: capturedAt,
            platform: platform,
            device: DeviceIdentity(
                id: "test-device",
                name: deviceName,
                model: "Test1,1",
                systemName: platform.rawValue,
                systemVersion: "1.0.0",
                architecture: "arm64"
            ),
            origin: origin,
            label: label,
            isPinned: isPinned,
            tags: tags,
            sections: sections
        )
    }
}

/// A minimal schema for tests that need a section but do not care what is in it.
public enum TestSchema {
    public static let capability = CapabilityID("test.widgets")
    public static let widget = EntityKind("widget")

    public static func make(
        privacy: PrivacyClassification = .local,
        comparison: ComparisonRule = .exact,
        severity: ChangeSeverity = .notable
    ) -> SectionSchema {
        SectionSchema(
            capability: capability,
            displayName: "Widgets",
            summary: "Test widgets.",
            category: .other,
            symbol: "square",
            privacy: privacy,
            entityKinds: [
                EntityKindDescriptor(
                    kind: widget,
                    singularName: "Widget",
                    pluralName: "Widgets",
                    symbol: "square",
                    additionSeverity: .notable,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(
                            key: "value",
                            displayName: "Value",
                            comparison: comparison,
                            severity: severity,
                            privacy: privacy,
                            isPrimary: true
                        ),
                        PropertyDescriptor(
                            key: "version",
                            displayName: "Version",
                            unit: .version,
                            severity: .significant,
                            isPrimary: true
                        ),
                        PropertyDescriptor(
                            key: "size",
                            displayName: "Size",
                            unit: .bytes,
                            severity: .informational
                        ),
                        PropertyDescriptor(
                            key: "secret",
                            displayName: "Secret",
                            severity: .notable,
                            privacy: .restricted
                        ),
                    ]
                ),
            ],
            attributes: [
                PropertyDescriptor(key: "total", displayName: "Total", unit: .count, severity: .notable),
            ]
        )
    }

    public static func section(
        entities: [SnapshotEntity],
        at date: Date = SnapshotBuilder.referenceDate,
        status: CollectionStatus = .collected,
        attributes: [PropertyKey: PropertyValue] = [:],
        schema: SectionSchema? = nil
    ) -> SnapshotSection {
        SnapshotSection(
            capability: capability,
            collector: "test.collector",
            collectorVersion: "1.0.0",
            collectedAt: date,
            duration: 0,
            status: status,
            schema: schema ?? make(),
            entities: entities,
            attributes: attributes
        )
    }

    public static func entity(
        _ id: String,
        name: String? = nil,
        value: PropertyValue = .string("a"),
        version: String? = nil,
        size: Int64? = nil
    ) -> SnapshotEntity {
        var properties: [PropertyKey: PropertyValue] = ["value": value]
        if let version {
            properties["version"] = .version(SemanticVersion(version) ?? "0.0.0")
        }
        if let size {
            properties["size"] = .bytes(size)
        }
        return SnapshotEntity(
            kind: widget,
            id: id,
            displayName: name ?? id,
            properties: properties
        )
    }
}

public extension SnapshotSummary {
    /// A timeline row with only the fields a retention or query test cares about.
    static func stub(
        id: String,
        capturedAt: Date,
        platform: Platform = .macOS,
        origin: SnapshotOrigin = .synthetic,
        label: String? = nil,
        isPinned: Bool = false,
        tags: Set<String> = [],
        deviceName: String = "Test Device",
        sectionCount: Int = 1,
        entityCount: Int = 1,
        problemCount: Int = 0
    ) -> SnapshotSummary {
        SnapshotSummary(
            id: SnapshotID(id),
            capturedAt: capturedAt,
            platform: platform,
            origin: origin,
            label: label,
            isPinned: isPinned,
            tags: tags,
            sectionCount: sectionCount,
            entityCount: entityCount,
            deviceName: deviceName,
            problemCount: problemCount
        )
    }
}

/// A small deterministic PRNG (xorshift64*).
///
/// `SystemRandomNumberGenerator` would make failures irreproducible, which is
/// the opposite of what a property test needs.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func shuffled<T>(_ values: [T]) -> [T] {
        values.shuffled(using: &self)
    }

    public mutating func pick<T>(_ values: [T]) -> T {
        values[int(in: 0 ... values.count - 1)]
    }

    public mutating func bool() -> Bool {
        int(in: 0 ... 1) == 1
    }
}

/// Scratch directory that tests delete in `defer`.
public enum TemporaryLibrary {
    public static func make(prefix: String = "diffuse-tests") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }
}
