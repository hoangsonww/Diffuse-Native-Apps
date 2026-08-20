import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Privacy ledger")
struct DomainPrivacyLedgerTests {
    private func makeLedger() async -> PrivacyLedger {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        await catalog.refresh()
        return await PrivacyLedger(statuses: catalog.statuses())
    }

    @Test("Never-collected commitments are explicit and include the hard lines")
    func neverCollected() {
        let items = PrivacyLedger.neverCollected
        #expect(items.count >= 8)
        #expect(items.contains { $0.localizedCaseInsensitiveContains("password") })
        #expect(items.contains { $0.localizedCaseInsensitiveContains("keychain") })
        #expect(items.contains { $0.localizedCaseInsensitiveContains("location") })
        #expect(items.contains { $0.localizedCaseInsensitiveContains("off the device") })
        #expect(items.contains { $0.localizedCaseInsensitiveContains("file contents") })
        #expect(items.contains { $0.localizedCaseInsensitiveContains("environment") })
    }

    @Test("Entries are ordered most sensitive first")
    func groupingOrder() async {
        let ledger = await makeLedger()
        let ranks = ledger.entries.map(\.privacy.rank)
        #expect(ranks == ranks.sorted(by: >))
        let groups = ledger.groupedByClassification.map(\.classification)
        #expect(groups == groups.sorted(by: >))
    }

    @Test("Markdown includes the never-collected list and every capability name")
    func markdown() async {
        let ledger = await makeLedger()
        let text = ledger.markdown()
        #expect(text.contains("# What Diffuse collects"))
        #expect(text.contains("Never collected"))
        for item in PrivacyLedger.neverCollected {
            #expect(text.contains(item))
        }
        for entry in ledger.entries {
            #expect(text.contains(entry.displayName))
        }
    }

    @Test("Redaction preview names capabilities that would lose fields")
    func redactionPreview() async {
        let catalog = CapabilityCatalog(registry: FakeCapabilityFactory.mixedRegistry())
        await catalog.refresh()
        let ledger = await PrivacyLedger(statuses: catalog.statuses())
        // TestSchema includes a restricted `secret` property, so even `.none` flags it.
        #expect(!ledger.redactedCapabilities(under: .none).isEmpty)
        #expect(!ledger.redactedCapabilities(under: .strict).isEmpty)
        #expect(ledger.redactedCapabilities(under: .strict).count >= ledger.redactedCapabilities(under: .none).count)
    }
}

@Suite("Redaction")
struct RedactionTests {
    private func snapshot(privacy: PrivacyClassification, value: String = "secret-ssid") -> Snapshot {
        let schema = TestSchema.make(privacy: privacy)
        return SnapshotBuilder()
            .withWidgets([TestSchema.entity("net", name: "HomeNet", value: .string(value))], schema: schema)
            .build()
    }

    @Test("Restricted values are redacted even under the none policy")
    func restrictedAlways() {
        let original = snapshot(privacy: .restricted)
        let redacted = original.redacted(.none)
        #expect(redacted.sections[0].entities[0].properties["value"] == .string("‹redacted›"))
        #expect(redacted.sections[0].entities[0].displayName == "‹redacted›")
        #expect(redacted.metadata.appliedRedaction == .none)
        #expect(original.sections[0].entities[0].properties["value"] != .string("‹redacted›"), "redaction is a copy")
    }

    @Test("Standard redacts sensitive but keeps local")
    func standard() {
        let sensitive = snapshot(privacy: .sensitive).redacted(.standard)
        #expect(sensitive.sections[0].entities[0].properties["value"] == .string("‹redacted›"))
        #expect(sensitive.metadata.appliedRedaction == .standard)

        let local = snapshot(privacy: .local).redacted(.standard)
        #expect(local.sections[0].entities[0].properties["value"] == .string("secret-ssid"))
    }

    @Test("Strict redacts local identifying values")
    func strict() {
        let local = snapshot(privacy: .local).redacted(.strict)
        #expect(local.sections[0].entities[0].properties["value"] == .string("‹redacted›"))
        #expect(local.metadata.appliedRedaction == .strict)
    }

    @Test("Public values survive every policy")
    func publicSurvives() {
        for policy in RedactionPolicy.allCases {
            let redacted = snapshot(privacy: .public, value: "macOS 26").redacted(policy)
            #expect(redacted.sections[0].entities[0].properties["value"] == .string("macOS 26"), "\(policy)")
        }
    }

    @Test("The none policy is a no-op when nothing is restricted")
    func noneIsIdentityForLocal() {
        let original = snapshot(privacy: .local)
        #expect(original.redacted(.none) == original)
    }

    @Test("Restricted properties are redacted even when the section is local")
    func perPropertyRestricted() {
        let schema = TestSchema.make(privacy: .local)
        let entity = TestSchema.entity("one")
        var properties = entity.properties
        properties["secret"] = .string("token")
        let snapshot = SnapshotBuilder()
            .withWidgets([
                SnapshotEntity(
                    kind: entity.kind,
                    id: entity.identity.value,
                    displayName: entity.displayName,
                    properties: properties
                ),
            ], schema: schema)
            .build()
        let redacted = snapshot.redacted(.none)
        #expect(redacted.sections[0].entities[0].properties["secret"] == .string("‹redacted›"))
        #expect(redacted.sections[0].entities[0].properties["value"] != .string("‹redacted›"))
    }

    @Test("RedactionPolicy.redacts matches the documented thresholds")
    func matrix() {
        let cases: [(RedactionPolicy, PrivacyClassification, Bool)] = [
            (.none, .public, false),
            (.none, .local, false),
            (.none, .sensitive, false),
            (.none, .restricted, true),
            (.standard, .public, false),
            (.standard, .local, false),
            (.standard, .sensitive, true),
            (.standard, .restricted, true),
            (.strict, .public, false),
            (.strict, .local, true),
            (.strict, .sensitive, true),
            (.strict, .restricted, true),
        ]
        for item in cases {
            #expect(item.0.redacts(item.1) == item.2, "\(item.0) vs \(item.1)")
        }
        #expect(RedactionPolicy.none.threshold == .restricted)
        #expect(RedactionPolicy.standard.threshold == .sensitive)
        #expect(RedactionPolicy.strict.threshold == .local)
    }

    @Test("Policy copy is written for the export sheet")
    func policyCopy() {
        #expect(RedactionPolicy.none.displayName == "Full detail")
        #expect(RedactionPolicy.standard.displayName == "Standard")
        #expect(RedactionPolicy.strict.displayName == "Strict")
        #expect(!RedactionPolicy.standard.summary.isEmpty)
        #expect(PrivacyClassification.restricted.displayName == "Restricted")
        #expect(PrivacyClassification.public.symbol == "globe")
        #expect(PrivacyClassification.sensitive > PrivacyClassification.local)
    }
}
