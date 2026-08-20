import DiffuseCore
import DiffuseDiff
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Change timeline")
struct DomainTimelineTests {
    private let t0 = SnapshotBuilder.referenceDate

    private func snap(_ id: String, offset: TimeInterval, value: String) -> Snapshot {
        SnapshotBuilder(id: id, capturedAt: t0.addingTimeInterval(offset))
            .withWidgets([TestSchema.entity("one", name: "Alpha", value: .string(value))])
            .build()
    }

    @Test("No snapshots produce no steps and a nil range")
    func empty() {
        let timeline = ChangeTimeline(snapshots: [])
        #expect(timeline.steps.isEmpty)
        #expect(timeline.clusters.isEmpty)
        #expect(timeline.range == nil)
        #expect(timeline.totalChanges == 0)
        #expect(timeline.allChanges.isEmpty)
    }

    @Test("A single snapshot produces no steps")
    func single() {
        let timeline = ChangeTimeline(snapshots: [snap("a", offset: 0, value: "1")])
        #expect(timeline.steps.isEmpty)
        #expect(timeline.range == t0 ... t0)
    }

    @Test("Three snapshots produce two steps even when input is shuffled")
    func pairwiseAndSort() {
        let a = snap("a", offset: 0, value: "1")
        let b = snap("b", offset: 60, value: "2")
        let c = snap("c", offset: 120, value: "3")
        let timeline = ChangeTimeline(snapshots: [c, a, b])
        #expect(timeline.steps.count == 2)
        #expect(timeline.steps[0].base.id == a.id)
        #expect(timeline.steps[0].target.id == b.id)
        #expect(timeline.steps[1].target.id == c.id)
        #expect(timeline.range == a.capturedAt ... c.capturedAt)
        #expect(timeline.totalChanges == timeline.steps.reduce(0) { $0 + $1.changeCount })
    }

    @Test("Identical consecutive snapshots still produce a step with an empty diff")
    func identicalPair() {
        let a = snap("a", offset: 0, value: "same")
        let b = snap("b", offset: 60, value: "same")
        let timeline = ChangeTimeline(snapshots: [a, b])
        #expect(timeline.steps.count == 1)
        #expect(timeline.steps[0].diff.isEmpty)
        #expect(timeline.steps[0].changeCount == 0)
    }

    @Test("Entity history is oldest-first and scoped to one identity")
    func history() {
        let timeline = ChangeTimeline(snapshots: [
            snap("a", offset: 0, value: "1"),
            snap("b", offset: 60, value: "2"),
            snap("c", offset: 120, value: "3"),
        ])
        let identity = EntityIdentity(kind: TestSchema.widget, value: "one")
        let history = timeline.history(of: identity)
        #expect(history.count == 2)
        #expect(history[0].observedAt <= history[1].observedAt)
        #expect(timeline.history(of: EntityIdentity(kind: TestSchema.widget, value: "missing")).isEmpty)
    }

    @Test("Most active capabilities honour the limit and break ties by id")
    func mostActive() {
        let timeline = ChangeTimeline(snapshots: [
            snap("a", offset: 0, value: "1"),
            snap("b", offset: 60, value: "2"),
        ])
        let ranked = timeline.mostActiveCapabilities(limit: 1)
        #expect(ranked.count == 1)
        #expect(ranked[0].capability == TestSchema.capability)
        #expect(timeline.mostActiveCapabilities(limit: 0).isEmpty)
    }

    @Test("Daily activity buckets by calendar day")
    func dailyActivity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let timeline = ChangeTimeline(snapshots: [
            snap("a", offset: 0, value: "1"),
            snap("b", offset: 60, value: "2"),
            snap("c", offset: 86400, value: "3"),
        ])
        let buckets = timeline.dailyActivity(calendar: calendar)
        #expect(buckets.count >= 1)
        #expect(buckets.map(\.count).reduce(0, +) == timeline.totalChanges)
        #expect(buckets.map(\.day) == buckets.map(\.day).sorted())
    }

    @Test("Step identifiers come from the underlying diff")
    func stepIdentity() {
        let timeline = ChangeTimeline(snapshots: [
            snap("a", offset: 0, value: "1"),
            snap("b", offset: 60, value: "2"),
        ])
        #expect(timeline.steps[0].id == timeline.steps[0].diff.id)
        #expect(timeline.steps[0].date == timeline.steps[0].target.capturedAt)
    }
}
