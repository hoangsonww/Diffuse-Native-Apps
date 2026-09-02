import DiffuseModels
import DiffuseStorage
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Retention planner")
struct RetentionPlannerTests {
    private let now = SnapshotBuilder.referenceDate

    /// Ages as an explicit `TimeInterval`. Written as a function rather than
    /// an integer expression inside the tuple literals below: older Swift
    /// cannot propagate the `Double` element type into a labelled-tuple array
    /// literal, so `10 * 86400` there infers as `Int` and fails to convert.
    private func days(_ count: Double) -> TimeInterval {
        count * 86400
    }

    private func summaries(_ specs: [(id: String, age: TimeInterval, pinned: Bool, label: String?)])
        -> [SnapshotSummary] {
        specs.map { spec in
            .stub(
                id: spec.id,
                capturedAt: now.addingTimeInterval(-spec.age),
                label: spec.label,
                isPinned: spec.pinned
            )
        }
    }

    @Test("Unlimited policy deletes nothing")
    func unlimitedKeepsEverything() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("new", days(0), false, nil),
                ("old", days(10), false, nil),
            ]),
            policy: .unlimited,
            now: now,
            averageBytesPerSnapshot: 1000
        )
        #expect(plan.isEmpty)
        #expect(plan.retainedCount == 2)
        #expect(plan.reclaimedBytes == 0)
    }

    @Test("The newest snapshot is never deleted, even when it is older than the window")
    func newestAlwaysSurvives() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([("only", days(400), false, nil)]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil, maximumCount: 1),
            now: now,
            averageBytesPerSnapshot: 1000
        )
        #expect(plan.deletions.isEmpty)
        #expect(plan.retainedCount == 1)
    }

    @Test("Age window marks unprotected snapshots older than the cutoff")
    func ageWindow() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(1), false, nil),
                ("stale", days(40), false, nil),
            ]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.deletions == [SnapshotID("stale")])
        #expect(plan.reasons[SnapshotID("stale")] == RetentionPlanner.Reason.tooOld)
    }

    @Test("Pinned snapshots survive the age window")
    func pinnedSurvivesAge() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(0), false, nil),
                ("keep", days(400), true, nil),
            ]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(!plan.deletions.contains(SnapshotID("keep")))
    }

    @Test("A labelled snapshot is protected by default")
    func labelledIsProtected() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(0), false, nil),
                ("named", days(400), false, "before the upgrade"),
            ]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(!plan.deletions.contains(SnapshotID("named")))
    }

    @Test("An empty label is not protection")
    func emptyLabelIsNotProtection() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(0), false, nil),
                ("blank", days(400), false, ""),
            ]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.deletions.contains(SnapshotID("blank")))
    }

    @Test("protectsLabelled can be turned off")
    func labelledProtectionCanBeDisabled() {
        let policy = RetentionPolicy(age: .days(30), maximumBytes: nil, protectsLabelled: false)
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(0), false, nil),
                ("named", days(400), false, "keep me"),
            ]),
            policy: policy,
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.deletions.contains(SnapshotID("named")))
    }

    @Test("Count limit keeps the newest unprotected snapshots")
    func countLimit() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("a", days(0), false, nil),
                ("b", 100, false, nil),
                ("c", 200, false, nil),
                ("d", 300, false, nil),
            ]),
            policy: RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: 2),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(Set(plan.deletions) == [SnapshotID("c"), SnapshotID("d")])
        #expect(plan.reasons.values.allSatisfy { $0 == .overCountLimit })
        #expect(plan.retainedCount == 2)
    }

    @Test("Pinned snapshots do not consume the count quota")
    func pinnedDoesNotConsumeQuota() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("newest", days(0), false, nil),
                ("pinned", 50, true, nil),
                ("extra", 100, false, nil),
            ]),
            policy: RetentionPolicy(age: .forever, maximumBytes: nil, maximumCount: 1),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.deletions == [SnapshotID("extra")])
        #expect(!plan.deletions.contains(SnapshotID("pinned")))
        #expect(!plan.deletions.contains(SnapshotID("newest")))
    }

    @Test("Size limit uses average bytes to compute an allowance of at least one")
    func sizeLimit() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("a", days(0), false, nil),
                ("b", days(10), false, nil),
                ("c", 20, false, nil),
            ]),
            policy: RetentionPolicy(age: .forever, maximumBytes: 150),
            now: now,
            averageBytesPerSnapshot: 100
        )
        // allowance = max(150/100, 1) = 1, so only the newest unprotected survives.
        #expect(Set(plan.deletions) == [SnapshotID("b"), SnapshotID("c")])
        #expect(plan.reasons.values.allSatisfy { $0 == .overSizeLimit })
        #expect(plan.reclaimedBytes == 200)
    }

    @Test("Zero average bytes skips the size pass rather than dividing by zero")
    func zeroAverageSkipsSize() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([("a", days(0), false, nil), ("b", days(10), false, nil)]),
            policy: RetentionPolicy(age: .forever, maximumBytes: 1),
            now: now,
            averageBytesPerSnapshot: 0
        )
        #expect(plan.isEmpty)
    }

    @Test("Age is applied before count, so a stale snapshot is tooOld not overCount")
    func ageWinsOverCount() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([
                ("fresh", days(0), false, nil),
                ("stale", days(40), false, nil),
            ]),
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil, maximumCount: 1),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.reasons[SnapshotID("stale")] == RetentionPlanner.Reason.tooOld)
    }

    @Test("Ties on capturedAt are broken by identifier")
    func identifierTieBreak() {
        let same = now.addingTimeInterval(-40 * 86400)
        let plan = RetentionPlanner.plan(
            summaries: [
                .stub(id: "z", capturedAt: now),
                .stub(id: "b", capturedAt: same),
                .stub(id: "a", capturedAt: same),
            ],
            policy: RetentionPolicy(age: .days(30), maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(Set(plan.deletions) == [SnapshotID("a"), SnapshotID("b")])
    }

    @Test("Forever age never emits tooOld")
    func foreverNeverTooOld() {
        let plan = RetentionPlanner.plan(
            summaries: summaries([("ancient", days(10000), false, nil), ("new", days(0), false, nil)]),
            policy: RetentionPolicy(age: .forever, maximumBytes: nil),
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.reasons.values.allSatisfy { $0 != RetentionPlanner.Reason.tooOld })
        #expect(plan.isEmpty)
    }

    @Test("Default policy keeps 90 days and a 1 GiB cap")
    func defaultPolicyShape() {
        #expect(RetentionPolicy.default.age == .days(90))
        #expect(RetentionPolicy.default.maximumBytes == 1_073_741_824)
        #expect(RetentionPolicy.default.protectsPinned)
        #expect(RetentionPolicy.default.protectsLabelled)
    }

    @Test("Age display names are stable")
    func ageDisplayNames() {
        #expect(RetentionPolicy.Age.forever.displayName == "Forever")
        #expect(RetentionPolicy.Age.days(30).displayName == "30 days")
        #expect(RetentionPolicy.Age.days(365).displayName == "1 year")
        #expect(RetentionPolicy.Age.days(730).displayName == "2 years")
        #expect(RetentionPolicy.Age.days(30).interval == TimeInterval(30 * 86400))
        #expect(RetentionPolicy.Age.forever.interval == nil)
    }

    @Test("Reason display names are written for the settings screen")
    func reasonCopy() {
        #expect(RetentionPlanner.Reason.tooOld.displayName.contains("Older"))
        #expect(RetentionPlanner.Reason.overCountLimit.displayName.contains("limit"))
        #expect(RetentionPlanner.Reason.overSizeLimit.displayName.contains("storage"))
    }

    @Test("isProtected matches the policy flags")
    func isProtected() {
        let pinned = SnapshotSummary.stub(id: "p", capturedAt: now, isPinned: true)
        let labelled = SnapshotSummary.stub(id: "l", capturedAt: now, label: "keep")
        let plain = SnapshotSummary.stub(id: "x", capturedAt: now)
        #expect(RetentionPolicy.default.isProtected(pinned))
        #expect(RetentionPolicy.default.isProtected(labelled))
        #expect(!RetentionPolicy.default.isProtected(plain))
        #expect(!RetentionPolicy(protectsPinned: false).isProtected(pinned))
    }

    @Test("An empty library produces an empty plan")
    func emptyLibrary() {
        let plan = RetentionPlanner.plan(
            summaries: [],
            policy: .default,
            now: now,
            averageBytesPerSnapshot: 100
        )
        #expect(plan.isEmpty)
        #expect(plan.retainedCount == 0)
    }
}
