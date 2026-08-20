import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Search index")
struct DomainSearchTests {
    private func snapshot(
        id: String,
        at offset: TimeInterval = 0,
        name: String,
        value: String
    ) -> Snapshot {
        SnapshotBuilder(id: id, capturedAt: SnapshotBuilder.referenceDate.addingTimeInterval(offset))
            .withWidgets([TestSchema.entity(id, name: name, value: .string(value))])
            .build()
    }

    @Test("Empty and whitespace queries return nothing")
    func emptyQuery() {
        let index = SearchIndex(snapshots: [snapshot(id: "a", name: "Alpha", value: "one")])
        #expect(index.search("").isEmpty)
        #expect(index.search("   ").isEmpty)
        #expect(index.search("\t\n").isEmpty)
    }

    @Test("All terms must match")
    func conjunction() {
        let index = SearchIndex(snapshots: [snapshot(id: "a", name: "Alpha Widget", value: "blue")])
        #expect(!index.search("alpha widget").isEmpty)
        #expect(index.search("alpha missing").isEmpty)
    }

    @Test("An exact title match outranks a prefix, which outranks a substring")
    func ranking() {
        let index = SearchIndex(snapshots: [
            snapshot(id: "exact", name: "node", value: "x"),
            snapshot(id: "prefix", name: "nodejs", value: "x"),
            snapshot(id: "sub", name: "mynodeapp", value: "x"),
        ])
        let results = index.search("node")
        #expect(results.map(\.title).first == "node")
        #expect(results.count == 3)
        #expect(results[0].score > results[1].score)
        #expect(results[1].score > results[2].score)
    }

    @Test("Limit truncates after ranking")
    func limit() {
        let snapshots = (0 ..< 12).map { i in
            snapshot(id: "w\(i)", name: "Widget \(i)", value: "shared")
        }
        let results = SearchIndex(snapshots: snapshots).search("widget", limit: 3)
        #expect(results.count == 3)
    }

    @Test("Newer snapshots win ties on equal scores")
    func recencyTieBreak() {
        let older = snapshot(id: "old", at: -3600, name: "SharedName", value: "a")
        let newer = snapshot(id: "new", at: 0, name: "SharedName", value: "a")
        let results = SearchIndex(snapshots: [older, newer]).search("sharedname")
        let titles = results.filter { $0.title == "SharedName" }
        #expect(titles.first?.date == newer.capturedAt)
    }

    @Test("Section names are searchable")
    func sectionName() {
        let results = SearchIndex(snapshots: [snapshot(id: "a", name: "Thing", value: "x")]).search("widgets")
        #expect(results.contains { $0.title == "Widgets" })
    }

    @Test("Property values are searchable")
    func propertyValue() {
        let results = SearchIndex(snapshots: [snapshot(id: "a", name: "Thing", value: "unique-token")])
            .search("unique-token")
        #expect(!results.isEmpty)
    }

    @Test("Change search with an empty query returns every change")
    func changeSearchEmpty() {
        let base = SnapshotBuilder(id: "b").withWidgets([TestSchema.entity("one", value: .string("a"))]).build()
        let target = SnapshotBuilder(id: "t").withWidgets([TestSchema.entity("one", value: .string("b"))]).build()
        let changes = DiffEngine().diff(base: base, target: target).changes
        #expect(ChangeSearchIndex(changes: changes).search("").count == changes.count)
        #expect(ChangeSearchIndex(changes: changes).search("   ").count == changes.count)
    }

    @Test("Change search filters by terms")
    func changeSearchFilter() {
        let base = SnapshotBuilder(id: "b").withWidgets([
            TestSchema.entity("one", name: "Alpha", value: .string("a")),
            TestSchema.entity("two", name: "Beta", value: .string("a")),
        ]).build()
        let target = SnapshotBuilder(id: "t").withWidgets([
            TestSchema.entity("one", name: "Alpha", value: .string("b")),
            TestSchema.entity("two", name: "Beta", value: .string("b")),
        ]).build()
        let changes = DiffEngine().diff(base: base, target: target).changes
        let hits = ChangeSearchIndex(changes: changes).search("alpha")
        #expect(hits.count == 1)
        #expect(hits[0].entity.displayName == "Alpha")
    }

    @Test("An index over no snapshots is empty")
    func emptyIndex() {
        #expect(SearchIndex(snapshots: []).search("anything").isEmpty)
    }
}
