import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

/// The small value types carry more behaviour than their size suggests —
/// namespacing, ordering, display names, symbols — and everything above them
/// assumes those rules hold.
@Suite("Value types")
struct ValueTypeTests {
    // MARK: - Identifiers

    @Test("A capability id splits into namespace and name at the first dot")
    func capabilityNamespaceAndName() {
        let id = CapabilityID("system.storage")
        #expect(id.namespace == "system")
        #expect(id.name == "storage")
        #expect(id.description == "system.storage")
        #expect(id.rawValue == "system.storage")
    }

    @Test("A capability id without a dot keeps the whole string as its name")
    func capabilityWithoutNamespace() {
        let id = CapabilityID("storage")
        #expect(id.name == "storage")
        // Namespace is either empty or the whole value, but never a crash and
        // never a partial word.
        #expect(id.namespace.isEmpty || id.namespace == "storage")
    }

    /// `namespace` is the leading segment and `name` the trailing one, so a
    /// three-part identifier drops its middle segment from both. Worth pinning:
    /// anything that round-trips through `namespace` + `name` would silently
    /// lose information for such an id.
    @Test("A capability id takes its namespace from the first segment and its name from the last")
    func capabilityWithNestedNamespace() {
        let id = CapabilityID("system.storage.volumes")
        #expect(id.namespace == "system")
        #expect(id.name == "volumes")
        #expect(id.rawValue == "system.storage.volumes", "the raw value keeps every segment")
    }

    @Test("Capability ids sort lexicographically and compare by raw value")
    func capabilityOrdering() {
        let ids = [CapabilityID("system.storage"), CapabilityID("app.git"), CapabilityID("system.display")]
        #expect(ids.sorted().map(\.rawValue) == ["app.git", "system.display", "system.storage"])
        #expect(CapabilityID("a") == CapabilityID(rawValue: "a"))
        #expect(CapabilityID("a") != CapabilityID("b"))
    }

    @Test("Capability and collector ids are expressible as string literals")
    func idsFromLiterals() {
        let capability: CapabilityID = "system.power"
        let collector: CollectorID = "mac.power"
        #expect(capability.rawValue == "system.power")
        #expect(collector.rawValue == "mac.power")
        #expect(collector.description == "mac.power")
    }

    @Test("Collector ids sort and dedupe by raw value")
    func collectorOrdering() {
        let set: Set<CollectorID> = ["b", "a", "a"]
        #expect(set.count == 2)
        #expect(set.sorted().map(\.rawValue) == ["a", "b"])
    }

    // MARK: - Platform

    @Test("Every declared platform has a display name and a symbol")
    func platformPresentation() {
        for platform in Platform.all {
            #expect(!platform.displayName.isEmpty, "\(platform) needs a display name")
            #expect(!platform.symbol.isEmpty, "\(platform) needs an SF Symbol")
            #expect(!platform.description.isEmpty)
        }
    }

    @Test("Platforms sort in a stable declared order")
    func platformOrdering() {
        let sorted = Platform.all.sorted()
        #expect(sorted.count == Platform.all.count)
        // Sorting twice gives the same answer.
        #expect(sorted.map(\.rawValue) == Platform.all.sorted().map(\.rawValue))
    }

    @Test("The current platform is one of the declared platforms")
    func currentPlatformIsKnown() {
        #expect(Platform.all.contains(Platform.current))
    }

    @Test("An unknown platform round-trips rather than being dropped")
    func unknownPlatformSurvives() {
        let exotic = Platform("carPlay")
        #expect(exotic.rawValue == "carPlay")
        #expect(!exotic.displayName.isEmpty)
        #expect(!exotic.symbol.isEmpty, "an unknown platform still needs a fallback symbol")
    }

    // MARK: - Severity

    @Test("Severity ranks strictly increase from informational to critical")
    func severityRanks() {
        #expect(ChangeSeverity.informational.rank < ChangeSeverity.notable.rank)
        #expect(ChangeSeverity.notable.rank < ChangeSeverity.significant.rank)
        #expect(ChangeSeverity.significant.rank < ChangeSeverity.critical.rank)
    }

    @Test("Severity comparison follows rank, and sorting is total")
    func severityComparable() {
        #expect(ChangeSeverity.informational < ChangeSeverity.critical)
        #expect(!(ChangeSeverity.critical < ChangeSeverity.informational))
        let sorted = ChangeSeverity.allCases.sorted()
        #expect(sorted.first == .informational)
        #expect(sorted.last == .critical)
    }

    @Test("Every severity has a display name and a symbol")
    func severityPresentation() {
        for severity in ChangeSeverity.allCases {
            #expect(!severity.displayName.isEmpty)
            #expect(!severity.symbol.isEmpty)
            #expect(!severity.rawValue.isEmpty)
        }
    }

    @Test("Severities round-trip through their raw values")
    func severityCodable() {
        for severity in ChangeSeverity.allCases {
            let restored = ChangeSeverity(rawValue: severity.rawValue)
            #expect(restored == severity)
        }
    }

    // MARK: - Snapshot sections

    @Test("Every collection status is decidable and has a raw value")
    func sectionStatusHasData() {
        for status in CollectionStatus.allCases {
            // hasData must be decidable for every status, not just the happy one.
            _ = status.hasData
            #expect(!status.rawValue.isEmpty)
        }
        #expect(CollectionStatus.collected.hasData)
        #expect(!CollectionStatus.unavailable.hasData)
    }

    @Test("A collected section exposes every entity it was built with")
    func sectionExposesEntities() {
        let section = TestSchema.section(entities: [
            TestSchema.entity("one"),
            TestSchema.entity("two"),
        ])

        #expect(section.entities.count == 2)
        #expect(section.allEntities.count >= section.entities.count)
        #expect(section.status == .collected)
        #expect(section.capability == TestSchema.capability)
    }

    @Test("An unavailable section carries no entities")
    func unavailableSectionIsEmpty() {
        let section = TestSchema.section(entities: [], status: .unavailable)
        #expect(section.entities.isEmpty)
        #expect(!section.status.hasData)
    }
}
