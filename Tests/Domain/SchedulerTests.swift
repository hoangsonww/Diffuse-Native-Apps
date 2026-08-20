import DiffuseCore
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

@Suite("Snapshot scheduler")
struct DomainSchedulerTests {
    private let now = SnapshotBuilder.referenceDate

    @Test("Cadence off with system events still counts as enabled")
    func systemEventsAloneEnableTheSchedule() {
        let schedule = SnapshotSchedule(cadence: .off, capturesOnSystemEvents: true)
        #expect(schedule.isEnabled)
        #expect(SnapshotScheduler.decide(schedule: schedule, lastCapture: nil, now: now) == .capture(reason: .firstRun))
    }

    @Test("Disabled is cadence off and no system events")
    func disabledShape() {
        #expect(!SnapshotSchedule.disabled.isEnabled)
        #expect(SnapshotSchedule.disabled.cadence == .off)
        #expect(!SnapshotSchedule.disabled.capturesOnSystemEvents)
    }

    @Test("Default cadence is every four hours with a 15-minute floor")
    func defaultShape() {
        #expect(SnapshotSchedule.default.cadence == .everyFourHours)
        #expect(SnapshotSchedule.default.minimumInterval == 900)
        #expect(SnapshotSchedule.default.capturesOnSystemEvents)
        #expect(SnapshotSchedule.default.skipsWhenUnchanged)
    }

    @Test("Hourly cadence waits until a full hour has elapsed")
    func hourlyWait() {
        let schedule = SnapshotSchedule(cadence: .hourly, capturesOnSystemEvents: false, minimumInterval: 60)
        let last = now.addingTimeInterval(-600)
        switch SnapshotScheduler.decide(schedule: schedule, lastCapture: last, now: now) {
        case let .wait(until):
            #expect(until == last.addingTimeInterval(3600))
        default:
            Issue.record("Expected wait")
        }
    }

    @Test("Daily cadence uses a 24-hour interval")
    func dailyCadence() {
        let schedule = SnapshotSchedule(cadence: .daily, capturesOnSystemEvents: false, minimumInterval: 60)
        let due = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-86500),
            now: now
        )
        #expect(due == .capture(reason: .cadenceElapsed))

        let waiting = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-3600),
            now: now
        )
        #expect(!waiting.shouldCapture)
    }

    @Test("Four-hour cadence sits between hourly and daily")
    func fourHourCadence() {
        #expect(SnapshotSchedule.Cadence.everyFourHours.interval == 14400)
        let schedule = SnapshotSchedule(cadence: .everyFourHours, capturesOnSystemEvents: false, minimumInterval: 60)
        let due = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-14401),
            now: now
        )
        #expect(due == .capture(reason: .cadenceElapsed))
    }

    @Test("System events are ignored when the schedule opts out")
    func systemEventOptOut() {
        let schedule = SnapshotSchedule(cadence: .daily, capturesOnSystemEvents: false, minimumInterval: 60)
        let decision = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-1000),
            now: now,
            systemEvent: true
        )
        #expect(!decision.shouldCapture)
    }

    @Test("Cadence off still captures on a system event after the floor")
    func cadenceOffSystemEvent() {
        let schedule = SnapshotSchedule(cadence: .off, capturesOnSystemEvents: true, minimumInterval: 900)
        let tooSoon = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-60),
            now: now,
            systemEvent: true
        )
        #expect(!tooSoon.shouldCapture)

        let allowed = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-1000),
            now: now,
            systemEvent: true
        )
        #expect(allowed == .capture(reason: .systemEvent))
    }

    @Test("Cadence off without a system event waits for the floor")
    func cadenceOffNoEventWaits() {
        let schedule = SnapshotSchedule(cadence: .off, capturesOnSystemEvents: true, minimumInterval: 900)
        switch SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-1000),
            now: now,
            systemEvent: false
        ) {
        case let .wait(until):
            #expect(until == now.addingTimeInterval(-1000).addingTimeInterval(900))
        default:
            Issue.record("Expected wait until the minimum interval")
        }
    }

    @Test("nextCaptureDate is nil when the schedule is disabled")
    func nextDateDisabled() {
        #expect(SnapshotScheduler.nextCaptureDate(schedule: .disabled, lastCapture: now, now: now) == nil)
    }

    @Test("nextCaptureDate is now when a capture is due")
    func nextDateDue() {
        let next = SnapshotScheduler.nextCaptureDate(
            schedule: .default,
            lastCapture: nil,
            now: now
        )
        #expect(next == now)
    }

    @Test("Decision.shouldCapture is true only for capture cases")
    func shouldCapture() {
        #expect(SnapshotScheduler.Decision.capture(reason: .firstRun).shouldCapture)
        #expect(!SnapshotScheduler.Decision.wait(until: now).shouldCapture)
        #expect(!SnapshotScheduler.Decision.disabled.shouldCapture)
    }

    @Test("Cadence display names are written for settings")
    func cadenceCopy() {
        #expect(SnapshotSchedule.Cadence.off.displayName == "Never")
        #expect(SnapshotSchedule.Cadence.hourly.displayName == "Every hour")
        #expect(SnapshotSchedule.Cadence.everyFourHours.displayName == "Every 4 hours")
        #expect(SnapshotSchedule.Cadence.daily.displayName == "Once a day")
        #expect(SnapshotScheduler.Reason.firstRun.displayName.contains("No previous"))
        #expect(SnapshotScheduler.Reason.systemEvent.displayName.contains("System"))
        #expect(SnapshotScheduler.Reason.cadenceElapsed.displayName.contains("interval"))
    }

    @Test("Exactly at the minimum interval is allowed")
    func exactlyAtFloor() {
        let schedule = SnapshotSchedule(cadence: .hourly, capturesOnSystemEvents: true, minimumInterval: 900)
        let decision = SnapshotScheduler.decide(
            schedule: schedule,
            lastCapture: now.addingTimeInterval(-900),
            now: now,
            systemEvent: true
        )
        #expect(decision == .capture(reason: .systemEvent))
    }

    @Test("Just under the minimum interval still waits")
    func justUnderFloor() {
        let schedule = SnapshotSchedule(cadence: .hourly, capturesOnSystemEvents: true, minimumInterval: 900)
        let last = now.addingTimeInterval(-899.5)
        switch SnapshotScheduler.decide(schedule: schedule, lastCapture: last, now: now, systemEvent: true) {
        case let .wait(until):
            #expect(until == last.addingTimeInterval(900))
        default:
            Issue.record("Expected wait")
        }
    }
}
