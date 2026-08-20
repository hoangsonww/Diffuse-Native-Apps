import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot query")
struct SnapshotQueryTests {
    private let now = SnapshotBuilder.referenceDate

    private var library: [SnapshotSummary] {
        [
            .stub(id: "mac-new", capturedAt: now, platform: .macOS, origin: .manual, label: "Latest", tags: ["work"]),
            .stub(
                id: "ios-mid",
                capturedAt: now.addingTimeInterval(-3600),
                platform: .iOS,
                origin: .scheduled,
                tags: ["travel"],
                deviceName: "Phone"
            ),
            .stub(
                id: "mac-old",
                capturedAt: now.addingTimeInterval(-7200),
                platform: .macOS,
                origin: .triggered,
                isPinned: true,
                tags: ["work", "lab"],
                deviceName: "Studio"
            ),
            .stub(
                id: "watch",
                capturedAt: now.addingTimeInterval(-10800),
                platform: .watchOS,
                origin: .imported,
                label: "Wrist"
            ),
        ]
    }

    @Test("all returns every summary, newest first")
    func allNewestFirst() {
        let ids = SnapshotQuery.all.apply(to: library).map(\.id.rawValue)
        #expect(ids == ["mac-new", "ios-mid", "mac-old", "watch"])
    }

    @Test("oldestFirst reverses the timeline")
    func oldestFirst() {
        let ids = SnapshotQuery(sort: .oldestFirst).apply(to: library).map(\.id.rawValue)
        #expect(ids == ["watch", "mac-old", "ios-mid", "mac-new"])
    }

    @Test("Platform filter keeps only matching devices")
    func platformFilter() {
        let ids = SnapshotQuery(platforms: [.macOS]).apply(to: library).map(\.id.rawValue)
        #expect(ids == ["mac-new", "mac-old"])
    }

    @Test("Origin filter keeps scheduled captures")
    func originFilter() {
        let ids = SnapshotQuery(origins: [.scheduled]).apply(to: library).map(\.id.rawValue)
        #expect(ids == ["ios-mid"])
    }

    @Test("pinnedOnly hides unpinned rows")
    func pinnedOnly() {
        let ids = SnapshotQuery(pinnedOnly: true).apply(to: library).map(\.id.rawValue)
        #expect(ids == ["mac-old"])
    }

    @Test("Tag filter is an OR of the requested tags")
    func tagDisjunction() {
        let ids = SnapshotQuery(tags: ["lab", "travel"]).apply(to: library).map(\.id.rawValue)
        #expect(Set(ids) == ["ios-mid", "mac-old"])
    }

    @Test("Search matches labels, device names and tags")
    func searchHaystack() {
        #expect(SnapshotQuery(searchText: "studio").apply(to: library).map(\.id.rawValue) == ["mac-old"])
        #expect(SnapshotQuery(searchText: "Wrist").apply(to: library).map(\.id.rawValue) == ["watch"])
        #expect(SnapshotQuery(searchText: "travel").apply(to: library).map(\.id.rawValue) == ["ios-mid"])
        #expect(SnapshotQuery(searchText: "phone").apply(to: library).map(\.id.rawValue) == ["ios-mid"])
    }

    @Test("Empty search text is ignored")
    func emptySearch() {
        #expect(SnapshotQuery(searchText: "").apply(to: library).count == 4)
        #expect(SnapshotQuery(searchText: nil).apply(to: library).count == 4)
    }

    @Test("Date range is a closed interval")
    func dateRange() {
        let range = now.addingTimeInterval(-7200) ... now.addingTimeInterval(-3600)
        let ids = SnapshotQuery(range: range).apply(to: library).map(\.id.rawValue)
        #expect(Set(ids) == ["ios-mid", "mac-old"])
    }

    @Test("limit and offset page stably")
    func paging() {
        let page = SnapshotQuery(limit: 2, offset: 1).apply(to: library).map(\.id.rawValue)
        #expect(page == ["ios-mid", "mac-old"])
        #expect(SnapshotQuery.recent(1).apply(to: library).map(\.id.rawValue) == ["mac-new"])
    }

    @Test("Offset past the end yields an empty page")
    func offsetPastEnd() {
        #expect(SnapshotQuery(offset: 40).apply(to: library).isEmpty)
    }

    @Test("Identical timestamps sort by identifier")
    func identifierTieBreak() {
        let same = now
        let rows = [
            SnapshotSummary.stub(id: "z", capturedAt: same),
            SnapshotSummary.stub(id: "a", capturedAt: same),
            SnapshotSummary.stub(id: "m", capturedAt: same),
        ]
        #expect(SnapshotQuery.all.apply(to: rows).map(\.id.rawValue) == ["a", "m", "z"])
        #expect(SnapshotQuery(sort: .oldestFirst).apply(to: rows).map(\.id.rawValue) == ["a", "m", "z"])
    }

    @Test("Filters compose: macOS + work tag + newest first")
    func composedFilters() {
        let ids = SnapshotQuery(platforms: [.macOS], tags: ["work"]).apply(to: library).map(\.id.rawValue)
        #expect(ids == ["mac-new", "mac-old"])
    }

    @Test("displayName prefers a label over the clock")
    func displayName() {
        let labelled = SnapshotSummary.stub(id: "x", capturedAt: now, label: "Before")
        let unlabelled = SnapshotSummary.stub(id: "y", capturedAt: now)
        #expect(labelled.displayName == "Before")
        #expect(!unlabelled.displayName.isEmpty)
        #expect(unlabelled.displayName != "Before")
    }

    @Test("Summary from a snapshot copies counts and annotations")
    func summaryFromSnapshot() {
        let snapshot = SnapshotBuilder(id: "s")
            .labelled("Keep")
            .pinned()
            .tagged(["lab"])
            .withWidgets([TestSchema.entity("one"), TestSchema.entity("two")])
            .build()
        let summary = SnapshotSummary(snapshot)
        #expect(summary.id == snapshot.id)
        #expect(summary.label == "Keep")
        #expect(summary.isPinned)
        #expect(summary.tags == ["lab"])
        #expect(summary.sectionCount == 1)
        #expect(summary.entityCount == 2)
        #expect(summary.deviceName == "Test Device")
    }
}
