import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Value comparator")
struct ValueComparatorTests {
    @Test("Exact equality is byte-for-byte")
    func exact() {
        #expect(ValueComparator.compare(.string("A"), .string("A"), rule: .exact).areEqual)
        #expect(!ValueComparator.compare(.string("A"), .string("a"), rule: .exact).areEqual)
        #expect(!ValueComparator.compare(.string("A"), .string("A "), rule: .exact).areEqual)
    }

    @Test("Case-insensitive comparison trims whitespace")
    func caseInsensitive() {
        #expect(ValueComparator.compare(.string("  Node  "), .string("node"), rule: .caseInsensitive).areEqual)
        #expect(!ValueComparator.compare(.string("node"), .string("deno"), rule: .caseInsensitive).areEqual)
        #expect(ValueComparator.compare(.integer(1), .integer(1), rule: .caseInsensitive).areEqual)
        #expect(!ValueComparator.compare(.integer(1), .integer(2), rule: .caseInsensitive).areEqual)
    }

    @Test("Path comparison collapses home and trailing slashes")
    func pathNormalized() {
        let home = NSHomeDirectory()
        #expect(
            ValueComparator.compare(
                .path(home + "/dev/app/"),
                .path("~/dev/app"),
                rule: .pathNormalized
            ).areEqual
        )
        #expect(!ValueComparator.compare(.path("/tmp/a"), .path("/tmp/b"), rule: .pathNormalized).areEqual)
    }

    @Test("Semantic versions treat 1.2 and 1.2.0 as equal")
    func semanticVersion() {
        let left = PropertyValue.version(SemanticVersion(1, 2))
        let right = PropertyValue.version(SemanticVersion(1, 2, 0))
        #expect(ValueComparator.compare(left, right, rule: .semanticVersion).areEqual)

        let bump = PropertyValue.version(SemanticVersion(1, 3, 0))
        let outcome = ValueComparator.compare(left, bump, rule: .semanticVersion)
        #expect(!outcome.areEqual)
        #expect(outcome.versionTransition != nil)
    }

    @Test("Unparseable versions fall back to literal comparison")
    func semanticFallback() {
        #expect(!ValueComparator.compare(.boolean(true), .boolean(false), rule: .semanticVersion).areEqual)
        #expect(ValueComparator.compare(.boolean(true), .boolean(true), rule: .semanticVersion).areEqual)
    }

    @Test("Numeric tolerance treats values inside the window as equal")
    func numericTolerance() {
        #expect(ValueComparator.compare(.double(10), .double(10.4), rule: .numeric(tolerance: 0.5)).areEqual)
        #expect(!ValueComparator.compare(.double(10), .double(11), rule: .numeric(tolerance: 0.5)).areEqual)
    }

    @Test("Relative tolerance scales with magnitude")
    func relativeTolerance() {
        #expect(ValueComparator.compare(.bytes(1000), .bytes(1009), rule: .relative(tolerance: 0.01)).areEqual)
        #expect(!ValueComparator.compare(.bytes(1000), .bytes(1020), rule: .relative(tolerance: 0.01)).areEqual)
        #expect(ValueComparator.compare(.integer(0), .integer(0), rule: .relative(tolerance: 0.01)).areEqual)
    }

    @Test("Confidence ramps from the threshold")
    func confidenceRamp() {
        let justOver = ValueComparator.compare(.double(10), .double(11.1), rule: .numeric(tolerance: 1))
        #expect(!justOver.areEqual)
        #expect(justOver.confidence < 1)

        let far = ValueComparator.compare(.double(10), .double(40), rule: .numeric(tolerance: 1))
        #expect(far.confidence == 1)
        #expect(far.relativeMagnitude != nil)
    }

    @Test("Unordered lists ignore element order")
    func unordered() {
        let a = PropertyValue.list([.string("b"), .string("a")])
        let b = PropertyValue.list([.string("a"), .string("b")])
        #expect(ValueComparator.compare(a, b, rule: .unordered).areEqual)
        #expect(!ValueComparator.compare(a, .list([.string("a")]), rule: .unordered).areEqual)
        #expect(ValueComparator.compare(.string("x"), .string("x"), rule: .unordered).areEqual)
    }

    @Test("Ignored values never produce a difference, including absent vs present")
    func ignored() {
        #expect(ValueComparator.compare(.string("a"), .string("b"), rule: .ignored).areEqual)
        #expect(ValueComparator.compare(.absent, .string("a"), rule: .ignored).areEqual)
    }

    @Test("Appearing or disappearing values are always different unless ignored")
    func absence() {
        #expect(ValueComparator.compare(.absent, .absent, rule: .exact).areEqual)
        #expect(!ValueComparator.compare(.absent, .string("a"), rule: .exact).areEqual)
        #expect(!ValueComparator.compare(.string("a"), .absent, rule: .numeric(tolerance: 5)).areEqual)
    }

    @Test("Default comparison rules follow the unit")
    func defaultRules() {
        #expect(ComparisonRule.default(for: .bytes) == .relative(tolerance: 0.01))
        #expect(ComparisonRule.default(for: .percent) == .numeric(tolerance: 0.05))
        #expect(ComparisonRule.default(for: .path) == .pathNormalized)
        #expect(ComparisonRule.default(for: .version) == .semanticVersion)
        #expect(ComparisonRule.default(for: .timestamp) == .ignored)
        #expect(ComparisonRule.default(for: .none) == .exact)
    }
}

@Suite("Semantic version")
struct SemanticVersionTests {
    private func parse(_ text: String) -> SemanticVersion? {
        SemanticVersion(text)
    }

    @Test("Parsing is lenient about a leading v and missing components")
    func parsing() {
        #expect(parse("v1") == SemanticVersion(1, 0, 0))
        #expect(parse("1.2") == SemanticVersion(1, 2, 0))
        #expect(parse("1.2.3-beta.1+build.7")?.prerelease == ["beta", "1"])
        #expect(parse("1.2.3+build.7")?.build == ["build", "7"])
        #expect(parse("") == nil)
        #expect(parse("not-a-version") == nil)
        #expect(parse("  2.0.0  ") == SemanticVersion(2, 0, 0))
    }

    @Test("A pre-release is less than the associated release")
    func prereleaseOrdering() throws {
        let alpha = try #require(parse("1.0.0-alpha"))
        let beta = try #require(parse("1.0.0-beta"))
        let release = try #require(parse("1.0.0"))
        let patch = try #require(parse("1.0.1"))
        let major = try #require(parse("2.0.0"))
        #expect(alpha < release)
        #expect(alpha < beta)
        #expect(release < patch)
        #expect(release < major)
    }

    @Test("Build metadata does not affect precedence")
    func buildIgnored() throws {
        let a = try #require(parse("1.0.0+aaa"))
        let b = try #require(parse("1.0.0+zzz"))
        #expect(!(a < b))
        #expect(!(b < a))
        #expect(a.hasSamePrecedence(as: b))
    }

    @Test("Transitions classify major, minor, patch and prerelease")
    func transitions() throws {
        let v100 = try #require(parse("1.0.0"))
        #expect(try v100.transition(to: #require(parse("2.0.0"))) == .major)
        #expect(try v100.transition(to: #require(parse("1.1.0"))) == .minor)
        #expect(try v100.transition(to: #require(parse("1.0.1"))) == .patch)
    }

    @Test("Description round-trips")
    func descriptionRoundTrip() {
        let original = SemanticVersion(1, 2, 3, prerelease: ["rc", "1"], build: ["exp"])
        #expect(parse(original.description) == original)
        #expect(original.description.contains("-rc.1"))
        #expect(original.description.contains("+exp"))
    }
}

@Suite("Change severity and classification")
struct SeverityTests {
    @Test("Severity ranks are strictly ordered")
    func order() {
        let cases = ChangeSeverity.allCases
        for (left, right) in zip(cases, cases.dropFirst()) {
            #expect(left < right)
            #expect(left.rank < right.rank)
        }
        #expect(ChangeSeverity.critical.displayName == "Critical")
        #expect(ChangeSeverity.informational.displayName == "Informational")
    }

    @Test("Privacy ranks are strictly ordered")
    func privacyOrder() {
        let cases = PrivacyClassification.allCases
        for (left, right) in zip(cases, cases.dropFirst()) {
            #expect(left < right)
        }
        #expect(!PrivacyClassification.sensitive.summary.isEmpty)
        #expect(PrivacyClassification.restricted.symbol == "lock.fill")
    }
}

@Suite("Platform and identifiers")
struct PlatformIdentifierTests {
    @Test("Known platforms have symbols and sort by raw value")
    func platforms() {
        #expect(Platform.all.contains(.macOS))
        #expect(Platform.all.contains(.watchOS))
        #expect(Platform.macOS.symbol == "macbook")
        #expect(Platform.iOS.symbol == "iphone")
        #expect(Platform.iPadOS.symbol == "ipad")
        #expect(Platform("unknown-future").symbol == "questionmark.square.dashed")
        #expect(Platform.iOS < Platform.macOS || Platform.macOS < Platform.iOS)
        #if os(macOS)
        #expect(Platform.current == .macOS)
        #endif
    }

    @Test("Snapshot IDs compare and shorten deterministically")
    func snapshotIDs() {
        let a = SnapshotID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(a.shortValue.count == 8)
        #expect(a.shortValue == a.shortValue.lowercased())
        #expect(SnapshotID("a") < SnapshotID("b"))
        #expect(SnapshotID("x").description == "x")
    }

    @Test("Entity identity normalizes case, whitespace and paths")
    func identityNormalization() {
        let left = EntityIdentity(kind: "repo", value: "  Foo   Bar  ")
        let right = EntityIdentity(kind: "repo", value: "foo bar")
        #expect(left == right)
        let path = EntityIdentity.path(kind: "repo", path: NSHomeDirectory() + "/dev/app/")
        #expect(path.value.contains("dev/app") || path.value.contains("~/dev/app") || path.value.hasPrefix("~"))
        #expect(!path.value.hasSuffix("/"))
    }

    @Test("Origins and collection statuses expose display names")
    func enums() {
        for origin in SnapshotOrigin.allCases {
            #expect(!origin.displayName.isEmpty)
            #expect(!origin.symbol.isEmpty)
        }
        for status in CollectionStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
        #expect(CollectionStatus.collected.hasData)
        #expect(CollectionStatus.partial.hasData)
        #expect(!CollectionStatus.failed.hasData)
        #expect(CollectionStatus.failed.isProblem)
        #expect(!CollectionStatus.collected.isProblem)
        #expect(!CollectionStatus.skipped.isProblem)
    }

    @Test("Device identity unknown is a stable fallback")
    func deviceUnknown() {
        #expect(DeviceIdentity.unknown.id == "unknown")
        #expect(!DeviceIdentity.unknown.name.isEmpty)
    }
}
