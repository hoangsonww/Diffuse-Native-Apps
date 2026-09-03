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

        HSplitView {
            picker
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
            result
                .frame(minWidth: 460)
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
                // Intrinsic width, not a cap: the picker carries a "Minimum
                // severity" label, and squeezing it renders that label one
                // character per line rather than truncating it. The split view
                // narrowed this pane, which is what exposed it.
                SeverityFilterBar(
                    minimumSeverity: $model.minimumSeverity,
                    summary: model.comparison?.summary ?? .empty
                )
                .fixedSize(horizontal: true, vertical: false)

                TextField("Filter changes", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 240)

                Spacer(minLength: 0)

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

    /// Always present. Choosing what to compare is part of comparing, so this
    /// list lives here rather than on the Snapshots tab — that tab is for
    /// reading one snapshot, this one is for diffing two.
    private var picker: some View {
        ScrollView {
            SnapshotPairPicker(
                summaries: model.summaries,
                selection: model.comparisonSelection,
                onToggle: { model.toggleComparison($0) },
                onCompareLatest: { model.compareLatest() },
                onClear: { model.clearComparison() }
            )
            .padding(DiffuseTheme.Spacing.regular)
        }
        .background(DiffuseTheme.Palette.canvas)
        .overlay {
            if !model.hasSnapshots {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No snapshots",
                    message: "Press ⌘N to capture the current state of this Mac."
                )
                .diffuseCanvas()
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var result: some View {
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
                                : "No changes match \u{201C}\(model.searchText)\u{201D}."
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
            .background(DiffuseTheme.Palette.canvas)
        } else {
            EmptyStateView(
                symbol: "arrow.left.arrow.right",
                title: model.canCompare ? "Pick two snapshots" : "Take another snapshot",
                message: model.canCompare
                    ? "Choose a pair on the left and the differences appear here."
                    : "Diffuse needs at least two snapshots before it can tell you what changed."
            ) {
                if !model.canCompare {
                    CaptureButton().frame(maxWidth: 240)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .diffuseCanvas()
        }
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
