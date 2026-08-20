import DiffuseCore
import DiffuseModels
import DiffuseStorage
import SwiftUI

/// Schedule, retention and export controls, shared so iPhone, iPad and Mac
/// cannot drift apart on the settings that actually change product behaviour.
public struct PreferenceSettingsSections: View {
    @Bindable private var preferences: DiffusePreferences
    private let model: DiffuseModel
    private let systemEventLabel: String?

    public init(
        preferences: DiffusePreferences,
        model: DiffuseModel,
        systemEventLabel: String? = nil
    ) {
        self.preferences = preferences
        self.model = model
        self.systemEventLabel = systemEventLabel
    }

    public var body: some View {
        Group {
            Section {
                Picker("Automatic snapshots", selection: $preferences.cadence) {
                    ForEach(SnapshotSchedule.Cadence.allCases, id: \.self) { cadence in
                        Text(cadence.displayName).tag(cadence)
                    }
                }
                if let systemEventLabel {
                    Toggle(systemEventLabel, isOn: $preferences.capturesOnSystemEvents)
                }
                Toggle("Skip unchanged automatic snapshots", isOn: $preferences.skipsWhenUnchanged)

                if let next = SnapshotScheduler.nextCaptureDate(
                    schedule: preferences.schedule,
                    lastCapture: model.latestSummary?.capturedAt,
                    now: Date()
                ) {
                    LabeledContent(
                        "Next automatic snapshot",
                        value: next.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text(scheduleFooter)
            }

            Section {
                Picker("Keep snapshots for", selection: $preferences.retentionDays) {
                    Text("Forever").tag(0)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                Picker("Maximum storage", selection: $preferences.maximumMegabytes) {
                    Text("No limit").tag(0)
                    Text("1 GB").tag(1024)
                    Text("5 GB").tag(5120)
                    Text("10 GB").tag(10240)
                }
            } header: {
                Text("Retention")
            } footer: {
                Text(
                    "Pinned and named snapshots are never removed automatically, and the most recent snapshot is always kept."
                )
            }

            Section {
                Picker("Redaction", selection: $preferences.redaction) {
                    ForEach(RedactionPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                Text(preferences.redaction.summary)
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            } header: {
                Text("Exports")
            }
        }
        .onChange(of: preferences.retentionDays) { _, _ in
            Task { await model.setRetentionPolicy(preferences.retentionPolicy) }
        }
        .onChange(of: preferences.maximumMegabytes) { _, _ in
            Task { await model.setRetentionPolicy(preferences.retentionPolicy) }
        }
    }

    private var scheduleFooter: String {
        if let systemEventLabel {
            "A minimum of 15 minutes always applies between automatic snapshots. \(systemEventLabel) still respects that floor."
        } else {
            "A minimum of 15 minutes always applies between automatic snapshots."
        }
    }
}
