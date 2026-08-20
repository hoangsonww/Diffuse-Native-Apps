import AppKit
import DiffuseModels
import DiffuseUI
import SwiftUI

/// The menu bar icon and its change count.
///
/// Kept to a glyph plus a number: the menu bar is a status surface, and a
/// status surface that shouts is one people remove.
struct MenuBarLabel: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.hexagongrid")
            if let count = changeCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
        }
    }

    private var changeCount: Int? {
        model.overview?.summary.totalChanges
    }
}

struct MenuBarContent: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            header
            Divider()

            if let overview = model.overview, overview.hasComparison {
                changeSummary(overview.summary)
                if !overview.topChanges.isEmpty {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                        ForEach(overview.topChanges.prefix(3)) { change in
                            ChangeRow(change, showsSection: true, isCompact: true)
                        }
                    }
                }
                Divider()
            }

            actions
        }
        .padding(DiffuseTheme.Spacing.regular)
        .frame(width: 320)
        .background(DiffuseTheme.Palette.canvas)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            DiffuseBrandMark(compact: true)
            Spacer()
            if let latest = model.latestSummary {
                Text(latest.capturedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            } else {
                Text("No snapshots")
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
        }
    }

    private func changeSummary(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            Text(summary.headline)
                .font(.subheadline.weight(.semibold))
            SeveritySummaryBar(summary: summary, height: 8, showsLegend: false)
        }
    }

    private var actions: some View {
        VStack(spacing: DiffuseTheme.Spacing.small) {
            Button {
                Task { await model.capture() }
            } label: {
                Label(model.phase == .capturing ? "Capturing…" : "Take Snapshot", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DiffuseTheme.Palette.accent)
            .disabled(model.phase.isBusy)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "workspace")
            } label: {
                Label("Open Diffuse", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("Quit Diffuse") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(DiffuseTheme.Palette.subtleText)
        }
    }
}
