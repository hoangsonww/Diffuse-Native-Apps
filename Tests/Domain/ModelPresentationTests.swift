import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

/// The model layer's presentation and state surfaces.
///
/// These are the properties every client reads directly to draw a row — value
/// formatting, status and severity vocabulary, section lookups, capability
/// availability. They have no behaviour of their own to unit test elsewhere,
/// and a mistake in one of them is a user-visible bug on four platforms at
/// once.
@Suite("Model presentation")
struct ModelPresentationTests {
    // MARK: - Property value formatting

    @Test("Every value case formats to something non-empty")
    func everyCaseFormats() {
        for value in allValueCases {
            #expect(!value.formatted().isEmpty, "\(value.typeName) formatted to nothing")
            #expect(!value.typeName.isEmpty)
        }
    }

    @Test("An absent value reads as an em dash rather than an empty cell")
    func absentFormatting() {
        #expect(PropertyValue.absent.formatted() == "—")
        #expect(PropertyValue.absent.isAbsent)
        #expect(PropertyValue.string("x").isAbsent == false)
        #expect(PropertyValue.absent.searchText.isEmpty, "an absent value must not match every search")
    }

    @Test("Booleans read as On and Off, and index under both spellings")
    func booleanFormatting() {
        #expect(PropertyValue.boolean(true).formatted() == "On")
        #expect(PropertyValue.boolean(false).formatted() == "Off")
        #expect(PropertyValue.boolean(true).searchText.contains("enabled"))
        #expect(PropertyValue.boolean(false).searchText.contains("disabled"))
        #expect(PropertyValue.boolean(true).numericValue == 1)
        #expect(PropertyValue.boolean(false).numericValue == 0)
    }

    /// Durations change unit as they grow, and each branch is a different code
    /// path — sub-second, sub-minute, and the calendar formatter above that.
    @Test("Duration formatting picks a unit appropriate to the magnitude")
    func durationFormatting() {
        #expect(PropertyValue.duration(0.25).formatted().hasSuffix("ms"))
        #expect(PropertyValue.duration(0.999).formatted().hasSuffix("ms"))
        #expect(PropertyValue.duration(1).formatted().hasSuffix("s"))
        #expect(PropertyValue.duration(42.5).formatted().hasSuffix("s"))

        let long = PropertyValue.duration(3600 * 5).formatted()
        #expect(!long.isEmpty)
        #expect(!long.hasSuffix("ms"))
    }

    @Test("Byte counts and percentages format as units, not bare numbers")
    func unitFormatting() {
        let bytes = PropertyValue.bytes(2_000_000).formatted()
        #expect(bytes.rangeOfCharacter(from: .letters) != nil, "a byte count needs a unit suffix")

        let percentage = PropertyValue.percentage(0.755).formatted()
        #expect(percentage.contains("%"))
    }

    /// Search must find `24.6.0` no matter how the value is displayed, so the
    /// index deliberately stores the raw text.
    @Test("Search text is unformatted so it matches what the user types")
    func searchTextIsRaw() {
        #expect(PropertyValue.bytes(2_000_000).searchText == "2000000")
        #expect(PropertyValue.integer(1500).searchText == "1500")
        #expect(PropertyValue.integer(1500).formatted() != "1500", "display formatting groups digits")
    }

    @Test("A compact path shows only the last component; standard shows all of it")
    func pathFormatting() {
        let path = PropertyValue.path("/usr/local/bin/node")
        #expect(path.formatted(style: .standard) == "/usr/local/bin/node")
        #expect(path.formatted(style: .compact) == "node")
        #expect(path.stringValue == "/usr/local/bin/node")
    }

    @Test("A compact list truncates past three entries and says how many remain")
    func listFormatting() {
        let short = PropertyValue.list([.string("a"), .string("b")])
        #expect(short.formatted(style: .compact) == "a, b")
        #expect(short.listValue?.count == 2)

        let long = PropertyValue.list((1 ... 6).map { .string("item\($0)") })
        let compact = long.formatted(style: .compact)
        #expect(compact.hasSuffix("+3 more"))
        #expect(!long.formatted(style: .standard).contains("more"), "the standard style shows everything")
    }

    @Test("A nested list indexes every leaf")
    func nestedListSearchText() {
        let nested = PropertyValue.list([.string("outer"), .list([.string("inner")])])
        #expect(nested.searchText.contains("outer"))
        #expect(nested.searchText.contains("inner"))
    }

    @Test("Only text-shaped cases expose a string, and only numeric cases a number")
    func accessorsAreTypeAware() {
        #expect(PropertyValue.identifier("abc").stringValue == "abc")
        #expect(PropertyValue.integer(1).stringValue == nil)
        #expect(PropertyValue.string("x").numericValue == nil)
        #expect(PropertyValue.list([]).numericValue == nil)
        #expect(PropertyValue.date(Date(timeIntervalSince1970: 10)).numericValue == 10)
    }

    /// A version stored as plain text still has to compare as a version, or a
    /// collector that emits `"1.2.3"` instead of `.version` would silently lose
    /// ordering.
    @Test("A version parses out of a string or identifier, but not out of prose")
    func versionAccessor() {
        #expect(PropertyValue.string("1.2.3").versionValue?.description == "1.2.3")
        #expect(PropertyValue.identifier("2.0.0").versionValue != nil)
        #expect(PropertyValue.integer(3).versionValue == nil)
    }

    @Test("Literals build the case they look like")
    func literals() {
        let text: PropertyValue = "hello"
        let count: PropertyValue = 42
        let ratio: PropertyValue = 1.5
        let flag: PropertyValue = true
        #expect(text.typeName == "string")
        #expect(count.typeName == "integer")
        #expect(ratio.typeName == "double")
        #expect(flag.typeName == "boolean")
    }

    @Test("Every value case survives a JSON round trip")
    func valuesRoundTrip() throws {
        for value in allValueCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
            #expect(decoded == value, "\(value.typeName) did not round-trip")
        }
    }

    @Test("An unknown value type is rejected rather than silently dropped")
    func unknownValueTypeIsRejected() throws {
        let payload = Data(#"{"type":"quaternion","value":1}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PropertyValue.self, from: payload)
        }
    }

    // MARK: - Collection status

    @Test("Only collected and partial sections carry data worth diffing")
    func statusHasData() {
        #expect(CollectionStatus.collected.hasData)
        #expect(CollectionStatus.partial.hasData)
        for status in CollectionStatus.allCases where status != .collected && status != .partial {
            #expect(!status.hasData, "\(status) must not be diffed")
        }
    }

    /// A skipped capability was the user's own choice and an unsupported one is
    /// the platform's — neither is something to nag about.
    @Test("Only statuses the user could act on count as problems")
    func statusIsProblem() {
        #expect(!CollectionStatus.collected.isProblem)
        #expect(!CollectionStatus.skipped.isProblem)
        #expect(!CollectionStatus.unsupported.isProblem)
        for status in [CollectionStatus.partial, .unavailable, .permissionRequired, .timedOut, .failed] {
            #expect(status.isProblem, "\(status) is actionable and must be surfaced")
        }
    }

    @Test("Every status has a distinct display name and a symbol")
    func statusVocabulary() {
        let names = CollectionStatus.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "two statuses must not read the same")
        #expect(CollectionStatus.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(CollectionStatus.allCases.allSatisfy { !$0.rawValue.isEmpty })
    }

    // MARK: - Severity

    @Test("Escalation and de-escalation saturate at the ends of the scale")
    func severitySaturates() {
        #expect(ChangeSeverity.informational.escalated() == .notable)
        #expect(ChangeSeverity.notable.escalated() == .significant)
        #expect(ChangeSeverity.significant.escalated() == .critical)
        #expect(ChangeSeverity.critical.escalated() == .critical, "critical cannot escalate further")

        #expect(ChangeSeverity.critical.deescalated() == .significant)
        #expect(ChangeSeverity.significant.deescalated() == .notable)
        #expect(ChangeSeverity.notable.deescalated() == .informational)
        #expect(ChangeSeverity.informational.deescalated() == .informational, "informational is the floor")
    }

    @Test("andAbove lists the severity itself and everything more severe")
    func severityAndAbove() {
        #expect(ChangeSeverity.critical.andAbove == [.critical])
        #expect(ChangeSeverity.informational.andAbove.count == ChangeSeverity.allCases.count)
        #expect(ChangeSeverity.significant.andAbove.allSatisfy { $0 >= .significant })
        #expect(ChangeSeverity.notable.andAbove.contains(.notable), "the threshold is inclusive")
    }

    @Test("Every severity and kind has a distinct display name")
    func severityAndKindVocabulary() {
        let severities = ChangeSeverity.allCases.map(\.displayName)
        #expect(Set(severities).count == severities.count)

        let kinds = ChangeKind.allCases.map(\.displayName)
        #expect(Set(kinds).count == kinds.count)
        #expect(ChangeKind.allCases.allSatisfy { !$0.rawValue.isEmpty })
    }

    // MARK: - Section categories

    @Test("Well-known categories sort in their declared order and unknowns sort last")
    func categoryOrdering() {
        let sorted = SectionCategory.wellKnown.shuffled().sorted()
        #expect(sorted == SectionCategory.wellKnown)

        let exotic = SectionCategory("quantum")
        #expect(exotic.sortIndex == SectionCategory.wellKnown.count)
        #expect(SectionCategory.system < exotic)
    }

    @Test("An unknown category still presents a name and a symbol")
    func unknownCategoryPresentation() {
        let exotic = SectionCategory("quantum")
        #expect(exotic.displayName == "Quantum", "the raw value is capitalised as a fallback")
        #expect(!exotic.symbol.isEmpty)
        #expect(exotic.description == "quantum")
    }

    @Test("Every well-known category has a distinct name and a symbol")
    func categoryVocabulary() {
        let names = SectionCategory.wellKnown.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(SectionCategory.wellKnown.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test("Categories are expressible as string literals")
    func categoryLiteral() {
        let category: SectionCategory = "system"
        #expect(category == .system)
    }

    // MARK: - Snapshot sections

    @Test("A section exposes its schema's presentation and its entities")
    func sectionLookups() {
        let section = TestSchema.section(entities: [
            TestSchema.entity("beta"),
            TestSchema.entity("alpha"),
        ])

        #expect(section.entityCount == 2)
        #expect(!section.displayName.isEmpty)
        #expect(!section.symbol.isEmpty)
        #expect(section.id == section.capability)
        #expect(section.entities(ofKind: TestSchema.widget).count == 2)
        #expect(section.entities(ofKind: EntityKind("absent")).isEmpty)
    }

    /// Sorted order is what the UI renders, so it must not depend on the order
    /// the collector happened to emit.
    @Test("Sorted entities are in identity order regardless of insertion order")
    func sectionSorting() {
        let forwards = TestSchema.section(entities: [TestSchema.entity("a"), TestSchema.entity("b")])
        let backwards = TestSchema.section(entities: [TestSchema.entity("b"), TestSchema.entity("a")])
        #expect(forwards.sortedEntities.map(\.id) == backwards.sortedEntities.map(\.id))
    }

    @Test("An entity can be found by identity, and an unknown identity returns nil")
    func sectionEntityLookup() {
        let wanted = TestSchema.entity("wanted")
        let section = TestSchema.section(entities: [wanted, TestSchema.entity("other")])

        #expect(section.entity(with: wanted.identity)?.id == wanted.id)
        #expect(section.entity(with: EntityIdentity(kind: TestSchema.widget, value: "ghost")) == nil)
    }

    /// A diagnostic id derived from its content is what keeps `diff(A, A)`
    /// empty; a generated one would make every snapshot unique.
    @Test("Diagnostic ids come from content, and levels are ordered")
    func diagnostics() {
        let first = Diagnostic(level: .warning, message: "slow", detail: "3s")
        let same = Diagnostic(level: .warning, message: "slow", detail: "3s")
        let other = Diagnostic(level: .error, message: "slow", detail: "3s")

        #expect(first.id == same.id)
        #expect(first.id != other.id)
        #expect(Diagnostic.Level.info < .warning)
        #expect(Diagnostic.Level.warning < .error)
        #expect(Diagnostic.Level.allCases.allSatisfy { !$0.symbol.isEmpty })
    }

    // MARK: - Capability availability

    @Test("Only the available state reports itself as available")
    func availabilityFlag() {
        #expect(CapabilityAvailability.available.isAvailable)
        for state in unavailableStates {
            #expect(!state.isAvailable)
        }
    }

    /// An unsupported capability should not clutter the UI at all; the others
    /// are worth showing so the user knows why data is missing.
    @Test("An unsupported capability is the only one hidden from discovery")
    func discoverability() {
        #expect(CapabilityAvailability.available.isDiscoverable)
        #expect(!CapabilityAvailability.unsupported(reason: "wrong platform").isDiscoverable)
        #expect(CapabilityAvailability.unavailable(reason: "no adapter").isDiscoverable)
    }

    /// Retrying a permission prompt or an unsupported platform can never
    /// succeed, so the UI must not offer it.
    @Test("Only states that could change on a retry are retryable")
    func retryability() {
        #expect(CapabilityAvailability.available.isRetryable)
        #expect(CapabilityAvailability.temporarilyUnavailable(reason: "busy").isRetryable)
        #expect(CapabilityAvailability.unavailable(reason: "no adapter").isRetryable)
        #expect(!CapabilityAvailability.unsupported(reason: "wrong platform").isRetryable)
        #expect(!CapabilityAvailability.permissionRequired(permission).isRetryable)
    }

    @Test("Only the available state has no explanation to show")
    func availabilityDetail() {
        #expect(CapabilityAvailability.available.detail == nil)
        #expect(CapabilityAvailability.unavailable(reason: "no adapter").detail == "no adapter")
        #expect(CapabilityAvailability.unsupported(reason: "wrong platform").detail == "wrong platform")
        #expect(CapabilityAvailability.temporarilyUnavailable(reason: "busy").detail == "busy")
        #expect(CapabilityAvailability.permissionRequired(permission).detail == permission.rationale)
    }

    /// A temporary outage is recorded the same way as a permanent one — the
    /// snapshot records what was seen, not why.
    @Test("Availability maps onto the collection status a snapshot would record")
    func availabilityToStatus() {
        #expect(CapabilityAvailability.available.collectionStatus == .collected)
        #expect(CapabilityAvailability.unavailable(reason: "x").collectionStatus == .unavailable)
        #expect(CapabilityAvailability.unsupported(reason: "x").collectionStatus == .unsupported)
        #expect(CapabilityAvailability.permissionRequired(permission).collectionStatus == .permissionRequired)
        #expect(CapabilityAvailability.temporarilyUnavailable(reason: "x").collectionStatus == .unavailable)
    }

    @Test("Every availability state has a distinct display name and a symbol")
    func availabilityVocabulary() {
        let states: [CapabilityAvailability] = [.available] + unavailableStates
        let names = states.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(states.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test("Every availability state survives a JSON round trip with its reason")
    func availabilityRoundTrips() throws {
        for state in [CapabilityAvailability.available] + unavailableStates {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(CapabilityAvailability.self, from: data)
            #expect(decoded == state, "\(state.displayName) did not round-trip")
            #expect(decoded.detail == state.detail, "the reason must survive too")
        }
    }

    // MARK: - Fixtures

    private var permission: PermissionRequirement {
        PermissionRequirement(id: "test.access", displayName: "Test Access", rationale: "So the test can read.")
    }

    private var unavailableStates: [CapabilityAvailability] {
        [
            .unavailable(reason: "no adapter"),
            .unsupported(reason: "wrong platform"),
            .permissionRequired(permission),
            .temporarilyUnavailable(reason: "busy"),
        ]
    }

    private var allValueCases: [PropertyValue] {
        [
            .string("text"),
            .integer(1500),
            .double(1.25),
            .boolean(true),
            .bytes(2_000_000),
            .duration(90),
            .percentage(0.5),
            .date(Date(timeIntervalSince1970: 1_700_000_000)),
            .version(SemanticVersion("1.2.3") ?? "0.0.0"),
            .identifier("com.example.app"),
            .path("/usr/local/bin/node"),
            .list([.string("a"), .string("b")]),
            .absent,
        ]
    }
}
