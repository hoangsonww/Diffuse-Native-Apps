import DiffuseModels
import Foundation

/// When Diffuse should take snapshots on its own.
public struct SnapshotSchedule: Sendable, Hashable, Codable {
    public enum Cadence: Sendable, Hashable, Codable, CaseIterable {
        case off
        case hourly
        case everyFourHours
        case daily

        public static var allCases: [Cadence] {
            [.off, .hourly, .everyFourHours, .daily]
        }

        public var interval: TimeInterval? {
            switch self {
            case .off: nil
            case .hourly: 3600
            case .everyFourHours: 14400
            case .daily: 86400
            }
        }

        public var displayName: String {
            switch self {
            case .off: "Never"
            case .hourly: "Every hour"
            case .everyFourHours: "Every 4 hours"
            case .daily: "Once a day"
            }
        }
    }

    public var cadence: Cadence

    /// Capture when the device wakes, unlocks or comes back from sleep.
    public var capturesOnSystemEvents: Bool

    /// Skip an automatic capture if nothing has changed since the last one.
    /// Prevents a timeline full of identical hourly snapshots.
    public var skipsWhenUnchanged: Bool

    /// Minimum spacing between automatic captures, regardless of triggers.
    public var minimumInterval: TimeInterval

    public init(
        cadence: Cadence = .everyFourHours,
        capturesOnSystemEvents: Bool = true,
        skipsWhenUnchanged: Bool = true,
        minimumInterval: TimeInterval = 900
    ) {
        self.cadence = cadence
        self.capturesOnSystemEvents = capturesOnSystemEvents
        self.skipsWhenUnchanged = skipsWhenUnchanged
        self.minimumInterval = minimumInterval
    }

    public static let `default` = SnapshotSchedule()
    public static let disabled = SnapshotSchedule(cadence: .off, capturesOnSystemEvents: false)

    public var isEnabled: Bool {
        cadence != .off || capturesOnSystemEvents
    }
}

/// Decides whether an automatic capture is due.
///
/// A pure decision function rather than a timer. Each platform drives it
/// differently — a `Timer` on macOS, `BGAppRefreshTask` on iOS, a
/// `WKApplicationRefreshBackgroundTask` on watchOS — but they all ask the same
/// question and get the same answer, and the answer is unit testable.
public enum SnapshotScheduler {
    public enum Decision: Sendable, Hashable {
        case capture(reason: Reason)
        case wait(until: Date)
        case disabled

        public var shouldCapture: Bool {
            if case .capture = self {
                return true
            }
            return false
        }
    }

    public enum Reason: String, Sendable, Hashable {
        case cadenceElapsed
        case systemEvent
        case firstRun

        public var displayName: String {
            switch self {
            case .cadenceElapsed: "Scheduled interval elapsed"
            case .systemEvent: "System event"
            case .firstRun: "No previous snapshot"
            }
        }
    }

    public static func decide(
        schedule: SnapshotSchedule,
        lastCapture: Date?,
        now: Date,
        systemEvent: Bool = false
    ) -> Decision {
        guard schedule.isEnabled else { return .disabled }

        guard let lastCapture else {
            return .capture(reason: .firstRun)
        }

        let elapsed = now.timeIntervalSince(lastCapture)

        // The floor applies to every trigger, including system events, so a
        // laptop that sleeps and wakes repeatedly does not fill the timeline.
        guard elapsed >= schedule.minimumInterval else {
            return .wait(until: lastCapture.addingTimeInterval(schedule.minimumInterval))
        }

        if systemEvent, schedule.capturesOnSystemEvents {
            return .capture(reason: .systemEvent)
        }

        guard let interval = schedule.cadence.interval else {
            return .wait(until: lastCapture.addingTimeInterval(schedule.minimumInterval))
        }

        if elapsed >= interval {
            return .capture(reason: .cadenceElapsed)
        }
        return .wait(until: lastCapture.addingTimeInterval(interval))
    }

    /// When the next automatic capture would happen, for the settings screen.
    public static func nextCaptureDate(
        schedule: SnapshotSchedule,
        lastCapture: Date?,
        now: Date
    ) -> Date? {
        switch decide(schedule: schedule, lastCapture: lastCapture, now: now) {
        case .capture: now
        case let .wait(until): until
        case .disabled: nil
        }
    }
}
