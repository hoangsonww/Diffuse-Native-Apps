import DiffuseCore
import DiffuseModels
import DiffuseStorage
import Foundation
import Observation

/// Schedule, retention and export preferences shared by every Diffuse app.
///
/// Mac-only concerns (watched repositories, the menu bar) stay in the Mac
/// target. Everything a phone, tablet or watch also needs to honour lives here,
/// persisted under the same `UserDefaults` keys so a setting chosen on one
/// screen is the setting the scheduler actually uses.
@MainActor
@Observable
public final class DiffusePreferences {
    public enum Key {
        public static let cadence = "diffuse.schedule.cadence"
        public static let capturesOnSystemEvents = "diffuse.schedule.systemEvents"
        public static let skipUnchanged = "diffuse.schedule.skipUnchanged"
        public static let retentionDays = "diffuse.retention.days"
        public static let maximumMegabytes = "diffuse.retention.megabytes"
        public static let redaction = "diffuse.export.redaction"
    }

    private let defaults: UserDefaults

    public var cadence: SnapshotSchedule.Cadence {
        didSet { defaults.set(Self.cadenceRawValue(cadence), forKey: Key.cadence) }
    }

    public var capturesOnSystemEvents: Bool {
        didSet { defaults.set(capturesOnSystemEvents, forKey: Key.capturesOnSystemEvents) }
    }

    public var skipsWhenUnchanged: Bool {
        didSet { defaults.set(skipsWhenUnchanged, forKey: Key.skipUnchanged) }
    }

    public var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Key.retentionDays) }
    }

    public var maximumMegabytes: Int {
        didSet { defaults.set(maximumMegabytes, forKey: Key.maximumMegabytes) }
    }

    public var redaction: RedactionPolicy {
        didSet { defaults.set(redaction.rawValue, forKey: Key.redaction) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cadence = Self.cadence(from: defaults.string(forKey: Key.cadence))
        capturesOnSystemEvents = defaults.object(forKey: Key.capturesOnSystemEvents) as? Bool ?? true
        skipsWhenUnchanged = defaults.object(forKey: Key.skipUnchanged) as? Bool ?? true
        retentionDays = defaults.object(forKey: Key.retentionDays) as? Int ?? 90
        maximumMegabytes = defaults.object(forKey: Key.maximumMegabytes) as? Int ?? 1024
        redaction = defaults.string(forKey: Key.redaction)
            .flatMap(RedactionPolicy.init(rawValue:)) ?? .standard
    }

    public var schedule: SnapshotSchedule {
        SnapshotSchedule(
            cadence: cadence,
            capturesOnSystemEvents: capturesOnSystemEvents,
            skipsWhenUnchanged: skipsWhenUnchanged
        )
    }

    public var retentionPolicy: RetentionPolicy {
        RetentionPolicy(
            age: retentionDays <= 0 ? .forever : .days(retentionDays),
            maximumBytes: maximumMegabytes <= 0 ? nil : Int64(maximumMegabytes) * 1_048_576
        )
    }

    /// `SnapshotSchedule.Cadence` has associated values, so it is persisted by
    /// a small stable token rather than by a synthesized raw value.
    public static func cadenceRawValue(_ cadence: SnapshotSchedule.Cadence) -> String {
        switch cadence {
        case .off: "off"
        case .hourly: "hourly"
        case .everyFourHours: "fourHours"
        case .daily: "daily"
        }
    }

    public static func cadence(from raw: String?) -> SnapshotSchedule.Cadence {
        switch raw {
        case "off": .off
        case "hourly": .hourly
        case "daily": .daily
        default: .everyFourHours
        }
    }
}
