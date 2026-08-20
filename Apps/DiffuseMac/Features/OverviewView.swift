import DiffuseCore
import DiffuseModels
import DiffuseUI
import SwiftUI

/// Answers "what is going on right now" in one screen.
struct OverviewView: View {
    @Environment(DiffuseModel.self) private var model
    var onShowComparison: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                if model.phase == .loading, !model.hasSnapshots {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 520)
                } else if !model.hasSnapshots {
                    emptyState
                } else {
                    header
                    if let overview = model.overview, overview.hasComparison {
                        sinceLastSnapshot(overview)
                    } else {
                        firstSnapshotNotice
                    }
                    if !model.actionableCapabilities.isEmpty {
                        permissionsCard
                    }
                    if let report = model.lastCaptureReport {
                        collectionHealth(report)
                    }
                }
            }
            .padding(DiffuseTheme.Spacing.large)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .diffuseCanvas()
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            DiffuseBrandMark()
            Text("Today's environment")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(DiffuseTheme.Palette.ink)

            if let latest = model.latestSummary {
                Text(
                    "Last snapshot \(latest.capturedAt.formatted(.relative(presentation: .named))) · \(latest.displayName)"
                )
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
        }
    }

    private func sinceLastSnapshot(_ overview: DiffuseCoreOverview) -> some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            Card {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                    HStack(alignment: .top) {
                        HeroMetric(
                            value: overview.summary.totalChanges,
                            caption: "since the previous snapshot"
                        )
                        Spacer()
                        Button("Open comparison") {
                            model.compareLatest()
                            onShowComparison()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DiffuseTheme.Palette.accent)
                    }

                    SeveritySummaryBar(summary: overview.summary)
                }
            }

            if !overview.topChanges.isEmpty {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    SectionHeaderLabel(
                        title: "Most significant",
                        symbol: "exclamationmark.circle",
                        subtitle: "The changes most likely to explain a difference in behaviour."
                    )
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(overview.topChanges.enumerated()), id: \.element.id) { index, change in
                                if index > 0 {
                                    Divider().padding(.vertical, DiffuseTheme.Spacing.small)
                                }
                                ChangeRow(change, showsSection: true)
                            }
                        }
                    }
                }
            }

            if !overview.clusters.isEmpty {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    SectionHeaderLabel(
                        title: "Change clusters",
                        symbol: "clock.arrow.2.circlepath",
                        subtitle: "Things that moved at roughly the same time."
                    )
                    ForEach(overview.clusters) { cluster in
                        ChangeClusterCard(cluster: cluster, changes: overview.changes(in: cluster))
                    }
                }
            }

            statistics(overview)
        }
    }

    private func statistics(_ overview: DiffuseCoreOverview) -> some View {
        Card {
            HStack(alignment: .top, spacing: DiffuseTheme.Spacing.large) {
                StatTile(count: overview.snapshotCount, label: "Snapshots", symbol: "camera.aperture")
                Divider().frame(height: 40)
                StatTile(
                    count: model.availableCapabilityCount,
                    label: "Capabilities",
                    symbol: "slider.horizontal.3",
                    tint: DiffuseTheme.Palette.added
                )
                Divider().frame(height: 40)
                StatTile(
                    value: model.formattedStorage,
                    label: "On disk",
                    symbol: "internaldrive",
                    tint: DiffuseTheme.Palette.informational
                )
            }
        }
    }

    private var firstSnapshotNotice: some View {
        Card {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                Label("One snapshot so far", systemImage: "camera.aperture")
                    .font(.headline)
                Text("Use your Mac as normal, then take another snapshot. Diffuse will show you exactly what "
                    + "changed in between.")
                    .font(.callout)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                Label("Some capabilities need permission", systemImage: "lock.circle.fill")
                    .font(.headline)
                    .foregroundStyle(DiffuseTheme.Palette.significant)

                ForEach(model.actionableCapabilities) { status in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.metadata.displayName)
                            .font(.subheadline.weight(.medium))
                        if let detail = status.availability.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if case let .permissionRequired(requirement) = status.availability,
                           let url = requirement.settingsURL {
                            Link("Open \(requirement.displayName)", destination: url)
                                .font(.caption.weight(.medium))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func collectionHealth(_ report: CaptureReport) -> some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            SectionHeaderLabel(
                title: report.problems.isEmpty ? "Last capture" : "Last capture had trouble",
                symbol: report.problems.isEmpty ? "stopwatch" : "exclamationmark.triangle",
                subtitle: report.problems.isEmpty
                    ? "Collectors run concurrently, and a slow one can never hold up the rest."
                    : "These collectors could not finish. Everything else in the snapshot is still usable."
            ) {
                Text("\(report.totalDuration, format: .number.precision(.fractionLength(2)))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }

            Card(padding: DiffuseTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 0) {
                    let rows = report.problems.isEmpty ? report.slowest(6) : Array(report.problems.prefix(6))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, outcome in
                        if index > 0 {
                            Divider().padding(.vertical, 6)
                        }
                        HStack(spacing: DiffuseTheme.Spacing.small) {
                            Image(systemName: outcome.symbol)
                                .imageScale(.small)
                                .foregroundStyle(outcome.status.color)
                            Text(outcome.displayName)
                                .font(.subheadline)
                            Spacer()
                            if report.problems.isEmpty {
                                Text("\(Int(outcome.duration * 1000)) ms")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            } else {
                                Text(outcome.status.displayName)
                                    .font(.caption)
                                    .foregroundStyle(outcome.status.color)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: "camera.aperture",
            title: "No snapshots yet",
            message: "Take a snapshot now, use your Mac, then take another. Diffuse compares the two and tells "
                + "you exactly what changed."
        ) {
            CaptureButton()
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 520)
    }
}

/// A local alias so the view signature does not leak the service type name.
typealias DiffuseCoreOverview = SnapshotService.Overview
