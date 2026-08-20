import DiffuseModels
import DiffuseUI
import SwiftUI

/// The comparison screen: the answer to "what changed between these two".
struct CompareView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(MacSettings.self) private var settings
    @State private var isCopied = false

    var body: some View {
        @Bindable var model = model

        Group {
            if let comparison = model.comparison {
                ScrollView {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                        Card { DiffHeaderView(diff: comparison) }

                        controls

                        if model.visibleChanges.isEmpty {
                            EmptyStateView(
                                symbol: "equal.circle",
                                title: model.searchText.isEmpty ? "Nothing changed" : "No matches",
                                message: model.searchText.isEmpty
                                    ? "These two snapshots are identical at this severity. Try lowering the filter."
                                    : "No changes match “\(model.searchText)”."
                            )
                            .frame(minHeight: 240)
                        } else {
                            ChangeListView(sections: model.visibleSections)
                        }

                        if !comparison.clusters.isEmpty {
                            clusters(comparison)
                        }
                    }
                    .padding(DiffuseTheme.Spacing.large)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                picker
            }
        }
        .diffuseCanvas()
        .toolbar {
            ToolbarItemGroup {
                Button {
                    copyReport()
                } label: {
                    Label(isCopied ? "Copied" : "Copy Report", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.comparison == nil)
                .help("Copy this comparison as Markdown (⇧⌘C)")

                Button {
                    model.clearComparison()
                } label: {
                    Label("Clear comparison", systemImage: "xmark.circle")
                }
                .disabled(model.comparison == nil)
                .help("Clear the selected snapshot pair")

                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Label("Clear filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var model = model

        return Card(padding: DiffuseTheme.Spacing.medium) {
            HStack(spacing: DiffuseTheme.Spacing.regular) {
                SeverityFilterBar(
                    minimumSeverity: $model.minimumSeverity,
                    summary: model.comparison?.summary ?? .empty
                )
                .frame(maxWidth: 360)

                TextField("Filter changes", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Spacer()

                Text("\(model.visibleChanges.count) shown")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
        }
    }

    private func clusters(_ comparison: DiffResult) -> some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            SectionHeaderLabel(
                title: "Change clusters",
                symbol: "clock.arrow.2.circlepath",
                subtitle: "Deterministic temporal grouping — changes seen within a few minutes of each other."
            )
            ForEach(comparison.clusters) { cluster in
                ChangeClusterCard(cluster: cluster, changes: comparison.changes(in: cluster))
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(spacing: DiffuseTheme.Spacing.large) {
            EmptyStateView(
                symbol: "arrow.left.arrow.right",
                title: model.canCompare ? "Pick two snapshots" : "Take another snapshot",
                message: model.canCompare
                    ? "Select two snapshots from the timeline, or compare the two most recent."
                    : "Diffuse needs at least two snapshots before it can tell you what changed."
            ) {
                if model.canCompare {
                    Button("Compare Latest Two") {
                        model.compareLatest()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DiffuseTheme.Palette.accent)
                    .keyboardShortcut("d", modifiers: [.command])
                } else {
                    CaptureButton().frame(maxWidth: 240)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, DiffuseTheme.Spacing.section)
    }

    private func copyReport() {
        Task {
            guard let report = await model.markdownReport(redaction: settings.redaction) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)

            withAnimation(DiffuseTheme.Motion.responsive) { isCopied = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DiffuseTheme.Motion.responsive) { isCopied = false }
        }
    }
}
