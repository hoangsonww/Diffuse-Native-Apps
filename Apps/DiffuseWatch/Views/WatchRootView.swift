import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import Foundation
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
            switch ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] {
            case "settings":
                WatchSettingsView()
            case "snapshot-detail":
                if let id = model.summaries.first?.id {
                    WatchSnapshotDetailView(id: id)
                } else {
                    ProgressView()
                }
            case "change-detail":
                if let change = model.overview?.topChanges.first {
                    WatchChangeDetailView(change: change)
                } else {
                    ProgressView()
                }
            default:
                glance
            }
        }
    }

    private var glance: some View {
        List {
            if !model.hasSnapshots {
                emptyState
            } else {
                summarySection
                changesSection
                historySection
            }

            actionsSection
        }
        .listStyle(.carousel)
        // The title carries information rather than repeating the app name: on a
        // watch the one thing worth the top line is how fresh this reading is.
        .navigationTitle(navigationTitle)
        .containerBackground(DiffuseTheme.Palette.accent.gradient.opacity(0.35), for: .navigation)
        .diffuseFailureBanner(model)
    }

    private var navigationTitle: String {
        guard let captured = model.latestSummary?.capturedAt else { return "Diffuse" }
        return captured.formatted(.relative(presentation: .named))
    }

    /// Primary and secondary actions live at the end of the list rather than in
    /// the navigation bar. A crown-scrolled list puts the last row under the
    /// thumb, and the top bar on a watch is too small to carry an icon that is
    /// not the screen's main job.
    private var actionsSection: some View {
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
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DiffuseTheme.Spacing.tight)
            }
            .disabled(model.phase.isBusy)
            .tint(DiffuseTheme.Palette.accent)
            .listRowBackground(
                RoundedRectangle(cornerRadius: DiffuseTheme.Radius.medium, style: .continuous)
                    .fill(DiffuseTheme.Palette.accent.opacity(0.22))
            )

            NavigationLink {
                WatchSettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.body)
                    .padding(.vertical, DiffuseTheme.Spacing.tight)
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Sections

    /// The hero. Uses the same `HeroMetric` and severity bar the Mac, iPad and
    /// iPhone overviews use, so the number reads identically on every device
    /// rather than being a watch-shaped imitation of it.
    private var summarySection: some View {
        Section {
            if let overview = model.overview, overview.hasComparison {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    // Short caption: the navigation title already says when this
                    // reading is from, and a two-line caption costs real estate
                    // a watch does not have.
                    HeroMetric(
                        value: overview.summary.totalChanges,
                        caption: "vs previous",
                        isCompact: true
                    )

                    SeveritySummaryBar(summary: overview.summary, height: 8, showsLegend: false)

                    if !severityCounts(overview.summary).isEmpty {
                        // Two badges already overflow a 46mm watch, and a
                        // clipped "2 Informa…" is worse than a second row.
                        // Same layout the Mac and iPad overviews use.
                        ChipFlowLayout(
                            horizontalSpacing: DiffuseTheme.Spacing.tight,
                            verticalSpacing: DiffuseTheme.Spacing.tight
                        ) {
                            ForEach(severityCounts(overview.summary), id: \.0) { severity, count in
                                SeverityBadge(severity, count: count)
                            }
                        }
                    }
                }
                .padding(.top, DiffuseTheme.Spacing.small)
                .padding(.bottom, DiffuseTheme.Spacing.medium)
            } else {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                    Text("One snapshot so far")
                        .font(.headline)
                        .foregroundStyle(DiffuseTheme.Palette.ink)
                    Text("Take another to see what changed.")
                        .font(.caption2)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DiffuseTheme.Spacing.small)
                .padding(.bottom, DiffuseTheme.Spacing.medium)
            }
        }
    }

    /// Severity chips, most severe first, skipping any severity with no changes.
    private func severityCounts(_ summary: DiffSummary) -> [(ChangeSeverity, Int)] {
        ChangeSeverity.allCases
            .sorted { $0.rank > $1.rank }
            .compactMap { severity in
                guard let count = summary.countsBySeverity[severity], count > 0 else { return nil }
                return (severity, count)
            }
    }

    @ViewBuilder
    private var changesSection: some View {
        if let overview = model.overview, !overview.topChanges.isEmpty {
            Section {
                ForEach(overview.topChanges.prefix(6)) { change in
                    NavigationLink {
                        WatchChangeDetailView(change: change)
                    } label: {
                        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                            HStack(spacing: DiffuseTheme.Spacing.tight) {
                                SeverityDot(change.severity, size: 6)
                                Text(change.sectionName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                    .lineLimit(1)
                            }
                            Text(change.summary)
                                .font(.caption)
                                .foregroundStyle(DiffuseTheme.Palette.ink)
                                .lineLimit(2)
                        }
                        .padding(.vertical, DiffuseTheme.Spacing.tight)
                    }
                }
            } header: {
                sectionHeader("Changes")
            }
        }
    }

    private var historySection: some View {
        Section {
            ForEach(model.summaries.prefix(8)) { summary in
                NavigationLink {
                    WatchSnapshotDetailView(id: summary.id)
                } label: {
                    HStack(spacing: DiffuseTheme.Spacing.small) {
                        Image(systemName: summary.origin.symbol)
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.accent)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(summary.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DiffuseTheme.Palette.ink)
                                .lineLimit(1)
                            Text(summary.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, DiffuseTheme.Spacing.tight)
                }
            }
        } header: {
            sectionHeader("History")
        }
    }

    /// Section headings share one treatment across the app, matching the
    /// uppercase tracked captions the Mac, iPad and iPhone clients use.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(DiffuseTheme.Palette.subtleText)
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                DiffuseGlyph(size: 32)
                Text("No snapshots yet")
                    .font(.headline)
                    .foregroundStyle(DiffuseTheme.Palette.ink)
                Text("Take one now, then another later.")
                    .font(.caption2)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DiffuseTheme.Spacing.small)
            .padding(.bottom, DiffuseTheme.Spacing.medium)
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
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                        Label(section.schema.displayName, systemImage: section.schema.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DiffuseTheme.Palette.ink)
                        StatusLabel(section.status)
                        ForEach(section.entities.prefix(4)) { entity in
                            Text(entity.displayName)
                                .font(.caption2)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, DiffuseTheme.Spacing.tight)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DiffuseTheme.Spacing.large)
            }
        }
        // `ink` is the text colour, not a page colour — using it here washed
        // every pushed screen out. `canvas` is the page token the other clients
        // paint behind their content.
        .containerBackground(DiffuseTheme.Palette.canvas.gradient, for: .navigation)
        .navigationTitle("Snapshot")
        .task { snapshot = await model.snapshot(id: id) }
    }
}

struct WatchChangeDetailView: View {
    let change: Change

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    // Severity leads, so the reason this change matters is the
                    // first thing read rather than a wall of identifier text.
                    SeverityBadge(change.severity)

                    // Long values — mount points, UUIDs, paths — are common here.
                    // Caption keeps them legible without letting one identifier
                    // fill the whole watch face.
                    Text(change.summary)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = change.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, DiffuseTheme.Spacing.small)
                .padding(.bottom, DiffuseTheme.Spacing.medium)
            }
        }
        // `ink` is the text colour, not a page colour — using it here washed
        // every pushed screen out. `canvas` is the page token the other clients
        // paint behind their content.
        .containerBackground(DiffuseTheme.Palette.canvas.gradient, for: .navigation)
        .navigationTitle(change.sectionName)
    }
}

struct WatchSettingsView: View {
    @Environment(DiffusePreferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        List {
            Section {
                Picker("Automatic snapshots", selection: $preferences.cadence) {
                    ForEach(SnapshotSchedule.Cadence.allCases, id: \.self) { cadence in
                        Text(cadence.displayName).tag(cadence)
                    }
                }
                Toggle("When I open the app", isOn: $preferences.capturesOnSystemEvents)
                Toggle("Skip unchanged", isOn: $preferences.skipsWhenUnchanged)
            } header: {
                Text("Schedule")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            } footer: {
                Text("Snapshots stay on this watch.")
                    .font(.caption2)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    .padding(.top, DiffuseTheme.Spacing.tight)
            }
        }
        // `ink` is the text colour, not a page colour — using it here washed
        // every pushed screen out. `canvas` is the page token the other clients
        // paint behind their content.
        .containerBackground(DiffuseTheme.Palette.canvas.gradient, for: .navigation)
        .navigationTitle("Settings")
    }
}
