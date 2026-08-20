import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot validator")
struct ValidatorTests {
    @Test("A well-formed widget snapshot has no problems")
    func healthySnapshot() {
        let snapshot = SnapshotBuilder().withWidgets([TestSchema.entity("one")]).build()
        #expect(SnapshotValidator.validate(snapshot).isEmpty)
    }

    @Test("An empty identifier is reported")
    func emptyIdentifier() {
        let snapshot = SnapshotBuilder(id: "").withWidgets([TestSchema.entity("one")]).build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("empty identifier") })
    }

    @Test("A capture date at the Unix epoch is rejected")
    func missingCaptureDate() {
        var snapshot = SnapshotBuilder().withWidgets([TestSchema.entity("one")]).build()
        snapshot = Snapshot(
            id: snapshot.id,
            capturedAt: Date(timeIntervalSince1970: 0),
            platform: snapshot.platform,
            device: snapshot.device,
            origin: snapshot.origin,
            sections: snapshot.sections
        )
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("no capture date") })
    }

    @Test("A future schema version is flagged")
    func futureSchema() {
        let base = SnapshotBuilder().withWidgets([TestSchema.entity("one")]).build()
        let snapshot = Snapshot(
            id: base.id,
            schemaVersion: SchemaVersion(base.schemaVersion.rawValue + 10),
            capturedAt: base.capturedAt,
            platform: base.platform,
            device: base.device,
            origin: base.origin,
            sections: base.sections
        )
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("newer than this build") })
    }

    @Test("Duplicate capabilities in one snapshot are illegal")
    func duplicateCapabilities() {
        let section = TestSchema.section(entities: [TestSchema.entity("one")])
        let snapshot = SnapshotBuilder().adding(section).adding(section).build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("appears more than once") })
    }

    @Test("A schema that names a different capability is illegal")
    func mismatchedSchemaCapability() {
        var schema = TestSchema.make()
        schema = SectionSchema(
            capability: "other.cap",
            displayName: schema.displayName,
            summary: schema.summary,
            category: schema.category,
            symbol: schema.symbol,
            privacy: schema.privacy,
            entityKinds: schema.entityKinds,
            attributes: schema.attributes
        )
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("one")], schema: schema))
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("schema declares capability") })
    }

    @Test("An empty schema display name is illegal")
    func emptySchemaName() {
        var schema = TestSchema.make()
        schema = SectionSchema(
            capability: schema.capability,
            displayName: "",
            summary: schema.summary,
            category: schema.category,
            symbol: schema.symbol,
            privacy: schema.privacy,
            entityKinds: schema.entityKinds,
            attributes: schema.attributes
        )
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("one")], schema: schema))
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("no display name") })
    }

    @Test("A failed section must not still carry entities")
    func failedSectionWithEntities() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(entities: [TestSchema.entity("one")], status: .failed))
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("still has entities") })
    }

    @Test("Duplicate entity identities inside a section are illegal")
    func duplicateIdentities() {
        let snapshot = SnapshotBuilder()
            .withWidgets([TestSchema.entity("dup"), TestSchema.entity("dup")])
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("duplicate entity identity") })
    }

    @Test("An entity with an empty display name is illegal")
    func emptyEntityName() {
        let snapshot = SnapshotBuilder()
            .withWidgets([TestSchema.entity("x", name: "")])
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("has no display name") })
    }

    @Test("An unknown entity kind is illegal")
    func unknownKind() {
        let entity = SnapshotEntity(kind: "nope", id: "x", displayName: "X", properties: ["value": .string("a")])
        let snapshot = SnapshotBuilder().withWidgets([entity]).build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("not described by the section schema") })
    }

    @Test("A property missing from the schema is illegal")
    func unknownProperty() {
        var entity = TestSchema.entity("one")
        entity = SnapshotEntity(
            kind: entity.kind,
            id: entity.identity.value,
            displayName: entity.displayName,
            properties: entity.properties.merging(["mystery": .string("x")]) { _, new in new }
        )
        let snapshot = SnapshotBuilder().withWidgets([entity]).build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("property 'mystery'") })
    }

    @Test("A section attribute missing from the schema is illegal")
    func unknownAttribute() {
        let snapshot = SnapshotBuilder()
            .adding(TestSchema.section(
                entities: [TestSchema.entity("one")],
                attributes: ["total": .integer(1), "mystery": .integer(2)]
            ))
            .build()
        let problems = SnapshotValidator.validate(snapshot)
        #expect(problems.contains { $0.contains("section attribute 'mystery'") })
    }

    @Test("JSON round-trip of a valid snapshot is silent")
    func roundTrip() throws {
        let snapshot = SnapshotBuilder(id: "round")
            .labelled("Keep")
            .pinned()
            .tagged(["lab"])
            .withWidgets([TestSchema.entity("one", version: "1.2.3", size: 42)])
            .build()
        #expect(SnapshotValidator.validate(snapshot).isEmpty)
        let encoded = try SnapshotCoding.encode(snapshot)
        let decoded = try SnapshotCoding.decodeSnapshot(encoded)
        #expect(decoded == snapshot)
        let reencoded = try SnapshotCoding.encode(decoded)
        #expect(reencoded == encoded)
    }

    @Test("Unavailable and skipped sections with no entities are valid")
    func emptyProblemSectionsAreValid() {
        for status in [CollectionStatus.unavailable, .skipped, .unsupported, .permissionRequired, .timedOut] {
            let snapshot = SnapshotBuilder()
                .adding(TestSchema.section(entities: [], status: status))
                .build()
            #expect(SnapshotValidator.validate(snapshot).isEmpty, "status \(status)")
        }
    }
}
