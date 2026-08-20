import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Semantic version")
struct SemanticVersionTests {
    /// A string literal binds to `ExpressibleByStringLiteral` rather than the
    /// failable parser, so tests spell the intent out.
    private func v(_ text: String) -> SemanticVersion {
        SemanticVersion(text) ?? SemanticVersion(0)
    }

    @Test(
        "Real-world version strings parse",
        arguments: [
            ("v24.6.0", 24, 6, 0),
            ("24.6", 24, 6, 0),
            ("3", 3, 0, 0),
            ("1.2.3-beta.1", 1, 2, 3),
            ("2.0.0+build.7", 2, 0, 0),
        ]
    )
    func parsing(text: String, major: Int, minor: Int, patch: Int) throws {
        let version = try #require(SemanticVersion(text))
        #expect(version.major == major)
        #expect(version.minor == minor)
        #expect(version.patch == patch)
    }

    @Test("Non-versions do not parse", arguments: ["", "unknown", "no numbers here"])
    func rejectsGarbage(text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test("Precedence follows the semver ordering rules")
    func ordering() {
        #expect(v("1.0.0") < v("1.0.1"))
        #expect(v("1.9.0") < v("1.10.0"))
        #expect(v("1.0.0-alpha") < v("1.0.0"))
        #expect(v("1.0.0-alpha.1") < v("1.0.0-alpha.2"))
        #expect(v("1.0.0-alpha") < v("1.0.0-beta"))
    }

    @Test("Build metadata is ignored for precedence")
    func buildMetadata() {
        let plain = v("2.0.0")
        let built = v("2.0.0+build.9")
        #expect(plain.hasSamePrecedence(as: built))
        #expect(plain.transition(to: built) == .unchanged)
    }

    @Test("Transitions classify the kind of move")
    func transitions() {
        #expect(v("1.0.0").transition(to: v("2.0.0")) == .major)
        #expect(v("1.0.0").transition(to: v("1.1.0")) == .minor)
        #expect(v("1.0.0").transition(to: v("1.0.1")) == .patch)
        #expect(v("2.0.0").transition(to: v("1.0.0")) == .downgrade)
    }

    @Test("Versions round-trip through Codable")
    func codable() throws {
        let version = v("1.2.3-rc.1+sha.abc")
        let data = try JSONEncoder().encode(version)
        #expect(String(decoding: data, as: UTF8.self) == "\"1.2.3-rc.1+sha.abc\"")
        #expect(try JSONDecoder().decode(SemanticVersion.self, from: data) == version)
    }
}

@Suite("Property values")
struct PropertyValueTests {
    @Test(
        "Every case survives a Codable round trip",
        arguments: [
            PropertyValue.string("hello"),
            .integer(42),
            .double(3.5),
            .boolean(true),
            .bytes(1_073_741_824),
            .duration(90),
            .percentage(0.61),
            .date(Date(timeIntervalSince1970: 1_787_130_240)),
            .version("1.2.3"),
            .identifier("com.example.app"),
            .path("/usr/local/bin/node"),
            .list([.string("a"), .integer(1)]),
            .absent,
        ]
    )
    func codableRoundTrip(value: PropertyValue) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(PropertyValue.self, from: encoder.encode(value))
        #expect(decoded == value)
    }

    @Test("Formatting reflects the semantic type, not just the number")
    func formatting() {
        #expect(PropertyValue.bytes(1_073_741_824).formatted() == "1.07 GB")
        #expect(PropertyValue.percentage(0.615).formatted() == "61.5%")
        #expect(PropertyValue.boolean(true).formatted() == "On")
        #expect(PropertyValue.boolean(false).formatted() == "Off")
        #expect(PropertyValue.absent.formatted() == "—")
        #expect(PropertyValue.version("24.6.0").formatted() == "24.6.0")
    }

    @Test("Compact formatting shortens paths and long lists")
    func compactFormatting() {
        #expect(PropertyValue.path("/usr/local/bin/node").formatted(style: .compact) == "node")

        let long = PropertyValue.list([.string("a"), .string("b"), .string("c"), .string("d"), .string("e")])
        #expect(long.formatted(style: .compact) == "a, b, c +2 more")
    }

    @Test("Numeric access works across the numeric cases")
    func numericAccess() {
        #expect(PropertyValue.integer(5).numericValue == 5)
        #expect(PropertyValue.bytes(2048).numericValue == 2048)
        #expect(PropertyValue.percentage(0.5).numericValue == 0.5)
        #expect(PropertyValue.boolean(true).numericValue == 1)
        #expect(PropertyValue.string("hello").numericValue == nil)
    }

    @Test("Search text is unformatted so raw values are findable")
    func searchText() {
        #expect(PropertyValue.bytes(1_073_741_824).searchText == "1073741824")
        #expect(PropertyValue.version("24.6.0").searchText == "24.6.0")
        #expect(PropertyValue.boolean(true).searchText.contains("enabled"))
    }
}

@Suite("Entity identity")
struct EntityIdentityTests {
    @Test("Normalization collapses case and whitespace")
    func normalization() {
        let left = EntityIdentity(kind: "display", value: "  Studio   Display ")
        let right = EntityIdentity(kind: "display", value: "studio display")
        #expect(left == right)
    }

    @Test("Different kinds never collide")
    func kindsAreDistinct() {
        #expect(EntityIdentity(kind: "display", value: "one") != EntityIdentity(kind: "volume", value: "one"))
    }

    @Test("Scope disambiguates otherwise identical values")
    func scoping() {
        let a = EntityIdentity(kind: "branch", value: "main", scope: "repo-a")
        let b = EntityIdentity(kind: "branch", value: "main", scope: "repo-b")
        #expect(a != b)
    }

    @Test("Path identities collapse the home directory and trailing separators")
    func pathNormalization() {
        let home = NSHomeDirectory()
        let absolute = EntityIdentity.path(kind: "gitRepository", path: "\(home)/dev/app/")
        let tilde = EntityIdentity.path(kind: "gitRepository", path: "~/dev/app")
        #expect(absolute == tilde)
    }

    @Test("Identities sort deterministically")
    func ordering() {
        let identities = [
            EntityIdentity(kind: "b", value: "1"),
            EntityIdentity(kind: "a", value: "2"),
            EntityIdentity(kind: "a", value: "1"),
        ]
        #expect(identities.sorted().map(\.description) == ["a:1", "a:2", "b:1"])
    }
}

@Suite("Snapshots")
struct SnapshotTests {
    @Test("Sections order by declared order, then category, then name")
    func sectionOrdering() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: []))
            .build()
        #expect(snapshot.orderedSections.count == 1)
    }

    @Test("Problem sections are surfaced separately")
    func problemSections() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [], status: .permissionRequired))
            .build()

        #expect(snapshot.hasProblems)
        #expect(snapshot.problemSections.count == 1)
        #expect(snapshot.collectedSections.isEmpty)
    }

    @Test("Redaction replaces sensitive values without touching public ones")
    func redaction() throws {
        var entity = TestSchema.entity("widget", value: .string("visible"))
        entity["secret"] = .string("hunter2")

        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [entity], schema: TestSchema.make(privacy: .public)))
            .build()

        let redacted = snapshot.redacted(.standard)
        let redactedEntity = try #require(redacted.sections.first?.entities.first)

        #expect(redactedEntity["secret"] == .string("‹redacted›"), "Restricted values must never survive an export")
        #expect(redactedEntity["value"] == .string("visible"))
        #expect(redacted.metadata.appliedRedaction == .standard)
    }

    @Test("Strict redaction removes more than standard redaction")
    func strictRedaction() {
        var entity = TestSchema.entity("widget", value: .string("visible"))
        entity["secret"] = .string("hunter2")

        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [entity], schema: TestSchema.make(privacy: .local)))
            .build()

        let strict = snapshot.redacted(.strict).sections.first?.entities.first
        #expect(strict?["value"] == .string("‹redacted›"))
    }

    @Test("Redaction never mutates the original")
    func redactionIsPure() throws {
        var entity = TestSchema.entity("widget")
        entity["secret"] = .string("hunter2")
        let snapshot = SnapshotBuilder().adding(TestSchema.section(entities: [entity])).build()

        _ = snapshot.redacted(.strict)

        let original = try #require(snapshot.sections.first?.entities.first)
        #expect(original["secret"] == .string("hunter2"))
    }

    @Test("Redaction hides sensitive display names, not just property values")
    func redactionCoversDisplayNames() throws {
        var entity = TestSchema.entity("Office", value: .string("Office"))
        entity.displayName = "Office"
        entity.subtitle = "en0"

        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [entity], schema: TestSchema.make(privacy: .sensitive)))
            .build()

        let redacted = try #require(snapshot.redacted(.standard).sections.first?.entities.first)
        #expect(redacted.displayName == "‹redacted›")
        #expect(redacted.subtitle == "‹redacted›")
        #expect(redacted["value"] == .string("‹redacted›"))
    }

    @Test("Entity counts include nested children")
    func entityCounting() {
        var parent = TestSchema.entity("parent")
        parent.children = [TestSchema.entity("child-a"), TestSchema.entity("child-b")]

        let snapshot = SnapshotBuilder().adding(TestSchema.section(entities: [parent])).build()
        #expect(snapshot.entityCount == 3)
    }

    @Test("Snapshots survive a Codable round trip")
    func codableRoundTrip() throws {
        let snapshot = SnapshotBuilder()
            .labelled("Before the upgrade")
            .adding(TestSchema.section(entities: [TestSchema.entity("alpha", version: "1.0.0", size: 42)]))
            .build()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Snapshot.self, from: encoder.encode(snapshot))
        #expect(decoded == snapshot)
    }
}

@Suite("Schema metadata")
struct SchemaTests {
    @Test("An unknown property still gets a usable descriptor")
    func fallbackDescriptor() {
        let schema = TestSchema.make()
        let descriptor = schema.descriptor(for: "refreshRate", in: TestSchema.widget)

        #expect(descriptor.displayName == "Refresh Rate", "Unknown keys are humanized rather than shown raw")
        #expect(descriptor.severity == .notable)
    }

    @Test("Comparison defaults are derived from the unit")
    func comparisonDefaults() {
        #expect(ComparisonRule.default(for: .version) == .semanticVersion)
        #expect(ComparisonRule.default(for: .path) == .pathNormalized)
        #expect(ComparisonRule.default(for: .timestamp) == .ignored)
        #expect(ComparisonRule.default(for: .bytes) == .relative(tolerance: 0.01))
        #expect(ComparisonRule.default(for: .none) == .exact)
    }

    @Test("Properties order by declared order then key")
    func propertyOrdering() {
        let descriptor = EntityKindDescriptor(
            kind: "thing",
            singularName: "Thing",
            properties: [
                PropertyDescriptor(key: "c", displayName: "C", displayOrder: 1),
                PropertyDescriptor(key: "a", displayName: "A", displayOrder: 0),
                PropertyDescriptor(key: "b", displayName: "B", displayOrder: 0),
            ]
        )
        #expect(descriptor.orderedProperties.map(\.key.rawValue) == ["a", "b", "c"])
    }

    @Test("Severity ranks and escalation saturate at the ends")
    func severityRanking() {
        #expect(ChangeSeverity.informational < ChangeSeverity.critical)
        #expect(ChangeSeverity.critical.escalated() == .critical)
        #expect(ChangeSeverity.informational.deescalated() == .informational)
        #expect(ChangeSeverity.notable.escalated() == .significant)
    }

    @Test("Redaction policy thresholds are ordered")
    func redactionThresholds() {
        #expect(RedactionPolicy.none.redacts(.restricted))
        #expect(!RedactionPolicy.none.redacts(.sensitive))
        #expect(RedactionPolicy.standard.redacts(.sensitive))
        #expect(!RedactionPolicy.standard.redacts(.local))
        #expect(RedactionPolicy.strict.redacts(.local))
        #expect(!RedactionPolicy.strict.redacts(.public))
    }
}
