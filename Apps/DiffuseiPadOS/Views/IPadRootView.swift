import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import Foundation
import SwiftUI
import UIKit

/// The iPad app is the analytical workspace: snapshots, changes and detail all
/// visible at once.
///
/// This is where Diffuse's comparison UI has the most room, so it is the one
/// place the three levels of the model — timeline, change, entity — are shown
/// side by side rather than pushed onto a stack.
struct IPadRootView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(DiffusePreferences.self) private var preferences
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedChange: Change?
    @State private var showsPrivacy = false
    @State private var showsCapabilities = false
    @State private var showsSettings = false
    @State private var inspectedID: SnapshotID?
    @State private var isConfirmingDeleteAll = false
    @State private var reportMarkdown = ""

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactSplit
            } else {
                threeColumnWorkspace
            }
        }
        .tint(DiffuseTheme.Palette.accent)
        .diffuseCanvas()
        .diffuseFailureBanner(model)
        .sheet(isPresented: $showsPrivacy) { privacySheet }
        .sheet(isPresented: $showsCapabilities) { capabilitiesSheet }
        .sheet(isPresented: $showsSettings) { settingsSheet }
        .onAppear {
            if sizeClass == .regular {
                columnVisibility = .all
            }
            if ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] == "privacy" {
                showsPrivacy = true
            }
            if ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] == "capabilities" {
                showsCapabilities = true
            }
        }
        .task {
            if sizeClass == .regular {
                columnVisibility = .all
            }
        }
        .onChange(of: sizeClass) { _, newValue in
            columnVisibility = newValue == .regular ? .all : .automatic
        }
        .onChange(of: model.comparisonSelection) { _, _ in selectedChange = nil }
        .onChange(of: model.summaries.count) { _, count in
            if count >= 2, ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] != nil {
                model.compareLatest()
            }
        }
        .onChange(of: model.latestSummary?.id) { _, _ in
            ChangeCountStore.iPadOS.publish(from: model)
        }
    }

    /// Slide Over / compact width keeps the system split view, which collapses
    /// to a stack. A 13-inch iPad has room for the whole workspace at once.
    private var compactSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            snapshotColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } content: {
            changeColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 520)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var threeColumnWorkspace: some View {
        HStack(spacing: 0) {
            NavigationStack { snapshotColumn }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            Rectangle()
                .fill(DiffuseTheme.Palette.hairline)
                .frame(width: 1)
            NavigationStack { changeColumn }
                .frame(minWidth: 320)
            Rectangle()
                .fill(DiffuseTheme.Palette.hairline)
                .frame(width: 1)
            NavigationStack { detailColumn }
                .frame(minWidth: 280)
        }
    }

    // MARK: - Column one: snapshots

    private var snapshotColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                if model.isSearchingLibrary {
                    LibrarySearchResultsView(results: model.libraryResults) { result in
                        if let id = result.snapshotID {
                            inspectedID = id
                        }
                    }
                } else {
                    SnapshotTimelineView(summaries: model.summaries) { summary in
                        Button {
                            model.toggleComparison(summary.id)
                        } label: {
                            TimelineRow(
                                summary: summary,
                                isSelected: model.comparisonSelection.contains(summary.id),
                                selectionOrder: model.selectionOrder(of: summary.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                model.toggleComparison(summary.id)
                            } label: {
                                Label(
                                    model.comparisonSelection.contains(summary.id)
                                        ? "Remove from Comparison"
                                        : "Add to Comparison",
                                    systemImage: "arrow.left.arrow.right"
                                )
                            }
                            Button {
                                Task { await model.setPinned(!summary.isPinned, for: summary.id) }
                            } label: {
                                Label(summary.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                            }
                            Button {
                                inspectedID = summary.id
                            } label: {
                                Label("Inspect", systemImage: "doc.text.magnifyingglass")
                            }
                            Button(role: .destructive) {
                                Task { await model.delete(id: summary.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(DiffuseTheme.Spacing.regular)
        }
        .diffuseCanvas()
        .navigationTitle("Snapshots")
        .searchable(
            text: Binding(
                get: { model.libraryQuery },
                set: { query in Task { await model.searchLibrary(query) } }
            ),
            prompt: "Search snapshots, apps, networks…"
        )
        .overlay {
            if model.phase == .loading, !model.hasSnapshots {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diffuseCanvas()
            } else if !model.hasSnapshots, !model.isSearchingLibrary {
                EmptyStateView(
                    symbol: "ipad.gen2",
                    title: "No snapshots",
                    message: "Take one to begin."
                ) {
                    Button {
                        Task { await model.capture() }
                    } label: {
                        Label(
                            model.phase == .capturing ? "Capturing…" : "Take Snapshot",
                            systemImage: "camera.aperture"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DiffuseTheme.Palette.accent)
                    .disabled(model.phase.isBusy)
                }
                .diffuseCanvas()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DiffuseTheme.Spacing.small) {
                Button {
                    Task { await model.capture() }
                } label: {
                    Label(
                        model.phase == .capturing ? "Capturing…" : "Take Snapshot",
                        systemImage: "camera.aperture"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DiffuseTheme.Palette.accent)
                .disabled(model.phase.isBusy)

                HStack(spacing: DiffuseTheme.Spacing.regular) {
                    Button("Capabilities") { showsCapabilities = true }
                    Button("Privacy") { showsPrivacy = true }
                    Button("Settings") { showsSettings = true }
                    Spacer()
                    Menu {
                        Button("Compare Latest Two", action: model.compareLatest)
                            .disabled(!model.canCompare)
                        Button("Delete All Snapshots…", role: .destructive) {
                            isConfirmingDeleteAll = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
                .font(.subheadline)
            }
            .padding(DiffuseTheme.Spacing.regular)
            .background(.bar)
        }
        .sheet(item: $inspectedID) { id in
            NavigationStack {
                IPadSnapshotDetailView(id: id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { inspectedID = nil }
                        }
                    }
            }
        }
        .confirmationDialog(
            "Delete every snapshot?",
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task { await model.deleteAll() }
            }
        } message: {
            Text(
                "This permanently removes your entire snapshot history, including pinned snapshots. It cannot be undone."
            )
        }
    }

    // MARK: - Column two: changes

    private var changeColumn: some View {
        @Bindable var model = model

        return Group {
            if let comparison = model.comparison {
                ScrollView {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                        Card { DiffHeaderView(diff: comparison, isCompact: true) }

                        SeverityFilterBar(minimumSeverity: $model.minimumSeverity, summary: comparison.summary)

                        if model.visibleChanges.isEmpty {
                            EmptyStateView(
                                symbol: "equal.circle",
                                title: model.searchText.isEmpty ? "Nothing changed" : "No matches",
                                message: model.searchText.isEmpty
                                    ? "These two snapshots match at this severity."
                                    : "No changes match “\(model.searchText)”."
                            )
                            .frame(minHeight: 280)
                        } else {
                            ChangeListView(sections: model.visibleSections) { change in
                                withAnimation(DiffuseTheme.Motion.responsive) { selectedChange = change }
                            }
                        }
                    }
                    .padding(DiffuseTheme.Spacing.regular)
                }
            } else {
                EmptyStateView(
                    symbol: "arrow.left.arrow.right",
                    title: model.canCompare ? "Select two snapshots" : "Take another snapshot",
                    message: model.canCompare
                        ? "Tap two snapshots on the left to compare them."
                        : "Diffuse needs two snapshots before it can compare anything."
                ) {
                    if model.canCompare {
                        Button("Compare Latest Two") { model.compareLatest() }
                            .buttonStyle(.borderedProminent)
                            .tint(DiffuseTheme.Palette.accent)
                    } else {
                        Button {
                            Task { await model.capture() }
                        } label: {
                            Label("Take Snapshot", systemImage: "camera.aperture")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DiffuseTheme.Palette.accent)
                        .disabled(model.phase.isBusy)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            }
        }
        .diffuseCanvas()
        .navigationTitle("Changes")
        .searchable(text: Binding(get: { model.searchText }, set: { model.searchText = $0 }), prompt: "Filter changes")
        .toolbar {
            if model.comparison != nil {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: IPadShareableReport(markdown: reportMarkdown),
                        preview: SharePreview("Diffuse report")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: model.comparison?.id) {
            reportMarkdown = await model.markdownReport(redaction: preferences.redaction) ?? ""
        }
    }

    // MARK: - Column three: detail

    @ViewBuilder
    private var detailColumn: some View {
        if let change = selectedChange {
            ChangeDetailView(change: change)
                .diffuseCanvas()
        } else if let comparison = model.comparison, !comparison.clusters.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                    SectionHeaderLabel(
                        title: "Change clusters",
                        symbol: "clock.arrow.2.circlepath",
                        subtitle: "Changes seen within a few minutes of each other."
                    )
                    ForEach(comparison.clusters) { cluster in
                        ChangeClusterCard(cluster: cluster, changes: comparison.changes(in: cluster))
                    }
                }
                .padding(DiffuseTheme.Spacing.regular)
            }
            .diffuseCanvas()
            .navigationTitle("Clusters")
        } else {
            EmptyStateView(
                symbol: "sidebar.right",
                title: "Select a change",
                message: "Pick a change in the middle column to see exactly what moved."
            )
            .diffuseCanvas()
        }
    }

    // MARK: - Sheets

    private var settingsSheet: some View {
        NavigationStack {
            List {
                PreferenceSettingsSections(
                    preferences: preferences,
                    model: model,
                    systemEventLabel: "Capture when I open the app"
                )
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
        }
    }

    private var privacySheet: some View {
        NavigationStack {
            PrivacySheetContent()
                .environment(model)
                .navigationTitle("Privacy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsPrivacy = false }
                    }
                }
        }
    }

    private var capabilitiesSheet: some View {
        NavigationStack {
            ScrollView {
                CapabilityListView(
                    statuses: model.capabilities,
                    onToggle: { id, isEnabled in
                        Task { await model.setCapabilityEnabled(isEnabled, for: id) }
                    },
                    onRequestPermission: { requirement in
                        let url = requirement.settingsURL ?? URL(string: UIApplication.openSettingsURLString)
                        if let url {
                            UIApplication.shared.open(url)
                        }
                    }
                )
                .padding(DiffuseTheme.Spacing.regular)
            }
            .diffuseCanvas()
            .navigationTitle("Capabilities")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.refreshCapabilities() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsCapabilities = false }
                }
            }
        }
    }
}

/// Everything known about one change, plus the entity it happened to.
struct ChangeDetailView: View {
    let change: Change
    @Environment(DiffuseModel.self) private var model
    @State private var entity: SnapshotEntity?
    @State private var schema: SectionSchema?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                Card {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                        HStack(spacing: DiffuseTheme.Spacing.small) {
                            SeverityBadge(change.severity)
                            Pill(change.kind.displayName, symbol: change.kind.symbol, tint: change.kind.color)
                            Pill(change.privacy.displayName, symbol: change.privacy.symbol, tint: change.privacy.color)
                        }

                        Text(change.summary)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        if let property = change.property {
                            PropertyChangeView(property, kind: change.kind)
                        }

                        if let detail = change.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        LabeledContent("Section", value: change.sectionName)
                        LabeledContent("Capability", value: change.capability.rawValue)
                        LabeledContent("Entity", value: change.entity.identity.description)
                        LabeledContent(
                            "Observed",
                            value: change.observedAt.formatted(date: .abbreviated, time: .standard)
                        )
                        if change.confidence < 1 {
                            LabeledContent("Confidence", value: "\(Int(change.confidence * 100))%")
                        }
                    }
                }

                if let entity, let schema {
                    EntityDetailView(entity: entity, schema: schema)
                }
            }
            .padding(DiffuseTheme.Spacing.regular)
        }
        .navigationTitle(change.entity.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: change.id) { await loadEntity() }
    }

    /// Loads the full entity from the later snapshot so the detail pane can
    /// show every property, not just the one that changed.
    private func loadEntity() async {
        guard
            let targetID = model.comparison?.target.id,
            let snapshot = await model.snapshot(id: targetID),
            let section = snapshot.section(for: change.capability)
        else {
            entity = nil
            schema = nil
            return
        }
        entity = section.entity(with: change.entity.identity)
        schema = section.schema
    }
}

struct PrivacySheetContent: View {
    @Environment(DiffuseModel.self) private var model
    @State private var ledger: PrivacyLedger?

    var body: some View {
        ScrollView {
            if let ledger {
                PrivacyLedgerView(ledger: ledger)
                    .padding(DiffuseTheme.Spacing.regular)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .diffuseCanvas()
        .task { ledger = await model.privacyLedger() }
    }
}

struct IPadSnapshotDetailView: View {
    let id: SnapshotID
    @Environment(DiffuseModel.self) private var model
    @State private var snapshot: Snapshot?
    @State private var inspected: IPadInspectedEntity?

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                    ForEach(snapshot.orderedSections) { section in
                        SnapshotSectionView(section: section) { entity in
                            inspected = IPadInspectedEntity(entity: entity, schema: section.schema)
                        }
                    }
                }
                .padding(DiffuseTheme.Spacing.regular)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .diffuseCanvas()
        .navigationTitle(snapshot?.displayName ?? "Snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $inspected) { item in
            ScrollView {
                EntityDetailView(entity: item.entity, schema: item.schema)
                    .padding(DiffuseTheme.Spacing.regular)
            }
            .diffuseCanvas()
            .navigationTitle(item.entity.displayName)
        }
        .task { snapshot = await model.snapshot(id: id) }
    }
}

private struct IPadInspectedEntity: Identifiable, Hashable {
    let entity: SnapshotEntity
    let schema: SectionSchema

    var id: EntityIdentity {
        entity.identity
    }
}

struct IPadShareableReport: Transferable {
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { report in
            Data(report.markdown.utf8)
        }
    }
}
