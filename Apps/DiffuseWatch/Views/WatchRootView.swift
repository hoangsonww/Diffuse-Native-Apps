import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI

/// The Watch app answers one question at a glance: what changed?
///
/// Deliberately not a miniature of the Mac app. There is no capability editor,
/// no export, no search — those belong on a device with a keyboard. What is
/// here is the summary, the changes, and the button to take another look.
struct WatchRootView: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if !model.hasSnapshots {
                    emptyState
                } else {
                    summarySection
                    changesSection
                    historySection
                }

                Section {
                    Button {
                        Task {
                            await model.capture()
                            await WatchComplicationBridge.publish(model: model)
                        }
                    } label: {
                        Label(
                            model.phase == .capturing ? "Capturing…" : "Take Snapshot",
                            systemImage: "camera.aperture"
                        )
                    }
                    .disabled(model.phase.isBusy)
                    .tint(DiffuseTheme.Palette.accent)
                    .listRowBackground(DiffuseTheme.Palette.accent.opacity(0.18))
                }
            }
            .navigationTitle("Diffuse")
            .toolbar {
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            .containerBackground(DiffuseTheme.Palette.ink.gradient, for: .navigation)
            .diffuseFailureBanner(model)
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            if let overview = model.overview, overview.hasComparison {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: DiffuseTheme.Spacing.tight) {
                        Text("Δ")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(DiffuseTheme.Palette.accent)
                        Text("\(overview.summary.totalChanges)")
                            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(overview.summary.totalChanges == 1 ? "change" : "changes")
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                    SeveritySummaryBar(summary: overview.summary, height: 6, showsLegend: false)
                }
                .padding(.vertical, 2)
            } else {
                Text("One snapshot so far")
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
        } header: {
            Text(model.latestSummary.map { $0.capturedAt.formatted(.relative(presentation: .named)) } ?? "Latest")
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        if let overview = model.overview, !overview.topChanges.isEmpty {
            Section("Changes") {
                ForEach(overview.topChanges.prefix(6)) { change in
                    NavigationLink {
                        WatchChangeDetailView(change: change)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DiffuseTheme.Spacing.tight) {
                                SeverityDot(change.severity, size: 6)
                                Text(change.sectionName)
                                    .font(.caption2)
                                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            }
                            Text(change.summary)
                                .font(.caption)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        Section("History") {
            ForEach(model.summaries.prefix(8)) { summary in
                NavigationLink {
                    WatchSnapshotDetailView(id: summary.id)
                } label: {
                    HStack(spacing: DiffuseTheme.Spacing.small) {
                        Image(systemName: summary.origin.symbol)
                            .font(.caption2)
                            .foregroundStyle(DiffuseTheme.Palette.accent)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(summary.displayName)
                                .font(.caption)
                            Text(summary.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                DiffuseGlyph(size: 32)
                Text("No snapshots yet")
                    .font(.headline)
                Text("Take one now, then another later.")
                    .font(.caption2)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
            .padding(.vertical, 4)
        }
    }
}

struct WatchSnapshotDetailView: View {
    let id: SnapshotID
    @Environment(DiffuseModel.self) private var model
    @State private var snapshot: Snapshot?

    var body: some View {
        List {
            if let snapshot {
                ForEach(snapshot.orderedSections) { section in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(section.schema.displayName, systemImage: section.schema.symbol)
                            .font(.caption.weight(.semibold))
                        StatusLabel(section.status)
                        ForEach(section.entities.prefix(4)) { entity in
                            Text(entity.displayName)
                                .font(.caption2)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Snapshot")
        .task { snapshot = await model.snapshot(id: id) }
    }
}

struct WatchChangeDetailView: View {
    let change: Change

    var body: some View {
        List {
            Section {
                Text(change.summary)
                    .font(.caption)
                if let detail = change.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                }
            }
            Section("Severity") {
                Label(change.severity.displayName, systemImage: change.severity.symbol)
            }
        }
        .navigationTitle(change.sectionName)
    }
}

struct WatchSettingsView: View {
    @Environment(DiffusePreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        List {
            Section("Schedule") {
                Picker("Automatic snapshots", selection: $preferences.cadence) {
                    ForEach(SnapshotSchedule.Cadence.allCases, id: \.self) { cadence in
                        Text(cadence.displayName).tag(cadence)
                    }
                }
                Toggle("When I open the app", isOn: $preferences.capturesOnSystemEvents)
                Toggle("Skip unchanged", isOn: $preferences.skipsWhenUnchanged)
            }
        }
        .navigationTitle("Settings")
    }
}
