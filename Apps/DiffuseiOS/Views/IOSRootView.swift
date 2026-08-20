import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import Foundation
import SwiftUI
import UIKit

/// iPhone navigation: a tab bar over navigation stacks.
///
/// Not a scaled-down Mac window. The phone answers a narrower question —
/// "what changed on this iPhone?" — with a compact timeline, cards and sheets.
struct IOSRootView: View {
    @Environment(DiffuseModel.self) private var model
    @State private var tab: IOSTab = .overview

    enum IOSTab: String, Hashable {
        case overview, timeline, compare, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                IOSOverviewView(onCompare: { tab = .compare })
            }
            .tabItem { Label("Overview", systemImage: "square.grid.2x2") }
            .tag(IOSTab.overview)

            NavigationStack {
                IOSTimelineView()
            }
            .tabItem { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
            .tag(IOSTab.timeline)

            NavigationStack {
                IOSCompareView()
            }
            .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
            .tag(IOSTab.compare)

            NavigationStack {
                IOSSettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(IOSTab.settings)
        }
        .toolbarBackground(DiffuseTheme.Palette.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .diffuseTabBarBehavior()
        .tint(DiffuseTheme.Palette.accent)
        .diffuseCanvas()
        .diffuseFailureBanner(model)
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"],
               let screen = IOSTab(rawValue: raw) {
                tab = screen
            }
        }
        .onChange(of: model.summaries.count) { _, count in
            if count >= 2, tab == .compare,
               ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] != nil {
                model.compareLatest()
            }
        }
        .onChange(of: model.latestSummary?.id) { _, _ in
            ChangeCountStore.iOS.publish(from: model)
        }
        .onChange(of: model.comparisonSelection) { _, selection in
            if selection.count == 2 {
                withAnimation(DiffuseTheme.Motion.responsive) { tab = .compare }
            }
        }
    }
}

// MARK: - Overview

struct IOSOverviewView: View {
    @Environment(DiffuseModel.self) private var model
    var onCompare: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                if model.phase == .loading, !model.hasSnapshots {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 480)
                } else if !model.hasSnapshots {
                    EmptyStateView(
                        symbol: "iphone.gen3",
                        title: "No snapshots yet",
                        message: "Take one now, use your iPhone, then take another. Diffuse will show you what "
                            + "changed in between."
                    ) {
                        IOSCaptureButton()
                    }
                    .frame(maxWidth: .infinity, minHeight: 480)
                } else {
                    if let overview = model.overview, overview.hasComparison {
                        summaryCard(overview)
                        if !overview.topChanges.isEmpty {
                            SectionHeaderLabel(
                                title: "Most significant",
                                symbol: "exclamationmark.circle",
                                subtitle: "The changes most likely to explain a difference in behaviour."
                            )
                            ForEach(overview.topChanges) { change in
                                Card(padding: DiffuseTheme.Spacing.medium) {
                                    ChangeRow(change, showsSection: true)
                                }
                            }
                        }
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                                DiffuseBrandMark()
                                Text("One snapshot so far")
                                    .font(.title3.weight(.semibold))
                                Text("Take another later and Diffuse will compare them.")
                                    .font(.callout)
                                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            }
                        }
                    }

                    if !model.actionableCapabilities.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                                Label("Some capabilities need permission", systemImage: "lock.circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(DiffuseTheme.Palette.significant)
                                ForEach(model.actionableCapabilities) { status in
                                    Text(status.metadata.displayName)
                                        .font(.subheadline.weight(.medium))
                                    if let detail = status.availability.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                    }
                                }
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Label("Open Settings", systemImage: "gear")
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, DiffuseTheme.Spacing.tight)
                            }
                        }
                    }

                    if let report = model.lastCaptureReport, !report.problems.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                                Label(
                                    "\(report.problems.count) collector\(report.problems.count == 1 ? "" : "s") had trouble",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.headline)
                                .foregroundStyle(DiffuseTheme.Palette.notable)
                                ForEach(report.problems.prefix(4)) { outcome in
                                    HStack {
                                        Image(systemName: outcome.symbol)
                                            .foregroundStyle(outcome.status.color)
                                        Text(outcome.displayName)
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    }

                    IOSCaptureButton()
                }
            }
            .padding(.horizontal, DiffuseTheme.Spacing.regular)
            .padding(.top, DiffuseTheme.Spacing.small)
            .padding(.bottom, DiffuseTheme.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .diffuseCanvas()
        .navigationTitle("Diffuse")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.capture() }
                } label: {
                    Image(systemName: model.phase == .capturing ? "hourglass" : "camera.aperture")
                }
                .disabled(model.phase.isBusy)
                .accessibilityLabel("Take Snapshot")
            }
        }
        .refreshable { await model.refresh() }
    }

    private func summaryCard(_ overview: SnapshotService.Overview) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                HeroMetric(
                    value: overview.summary.totalChanges,
                    caption: "since the previous snapshot",
                    isCompact: true
                )

                SeveritySummaryBar(summary: overview.summary)

                Button {
                    model.compareLatest()
                    onCompare()
                } label: {
                    Label("Open comparison", systemImage: "arrow.left.arrow.right")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(DiffuseTheme.Palette.accent)
            }
        }
    }
}

struct IOSCaptureButton: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        Button {
            Task { await model.capture() }
        } label: {
            Label(
                model.phase == .capturing ? "Capturing…" : "Take Snapshot",
                systemImage: model.phase == .capturing ? "hourglass" : "camera.aperture"
            )
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(DiffuseTheme.Palette.accent)
        .disabled(model.phase.isBusy)
        .sensoryFeedback(.success, trigger: model.summaries.count)
    }
}

// MARK: - Timeline

struct IOSTimelineView: View {
    @Environment(DiffuseModel.self) private var model
    @State private var openedID: SnapshotID?
    @State private var pendingDelete: SnapshotID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                if model.isSearchingLibrary {
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        LibrarySearchResultsView(results: model.libraryResults) { result in
                            openedID = result.snapshotID
                        }
                    }
                } else {
                    if model.canCompare {
                        Card(padding: DiffuseTheme.Spacing.medium) {
                            HStack(spacing: DiffuseTheme.Spacing.small) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(DiffuseTheme.Palette.accent)
                                Text(model.comparisonSelection.isEmpty
                                    ? "Long-press a snapshot to add it to a comparison, or swipe it."
                                    : "\(model.comparisonSelection.count) of 2 selected")
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    SnapshotTimelineView(summaries: model.summaries) { summary in
                        NavigationLink {
                            IOSSnapshotDetailView(id: summary.id)
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
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                model.toggleComparison(summary.id)
                            } label: {
                                Label("Compare", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(DiffuseTheme.Palette.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = summary.id
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { await model.setPinned(!summary.isPinned, for: summary.id) }
                            } label: {
                                Label(summary.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                            }
                            .tint(DiffuseTheme.Palette.notable)
                        }
                    }
                }
            }
            .padding(DiffuseTheme.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .navigationDestination(item: $openedID) { id in
            IOSSnapshotDetailView(id: id)
        }
        .overlay {
            if model.phase == .loading, !model.hasSnapshots {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diffuseCanvas()
            } else if !model.hasSnapshots, !model.isSearchingLibrary {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No snapshots",
                    message: "Snapshots you take will appear here, grouped by day."
                ) {
                    IOSCaptureButton()
                }
                .diffuseCanvas()
            }
        }
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Task { await model.delete(id: pendingDelete) }
                    self.pendingDelete = nil
                }
            }
        }
        .refreshable { await model.refresh() }
    }
}

struct IOSSnapshotDetailView: View {
    let id: SnapshotID
    @Environment(DiffuseModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: Snapshot?
    @State private var labelDraft = ""
    @State private var inspected: InspectedEntity?
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                    Card {
                        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                            TextField("Name this snapshot", text: $labelDraft)
                                .font(.headline)
                                .onSubmit { saveLabel() }
                            Text(snapshot.capturedAt.formatted(date: .complete, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        }
                    }
                    ForEach(snapshot.orderedSections) { section in
                        SnapshotSectionView(section: section) { entity in
                            inspected = InspectedEntity(entity: entity, schema: section.schema)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.toggleComparison(id)
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    if let snapshot {
                        Button {
                            Task { await model.setPinned(!snapshot.isPinned, for: id) }
                        } label: {
                            Label(snapshot.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                        }
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            snapshot = await model.snapshot(id: id)
            labelDraft = snapshot?.label ?? ""
        }
        .onDisappear { saveLabel() }
        .navigationDestination(item: $inspected) { item in
            ScrollView {
                EntityDetailView(entity: item.entity, schema: item.schema)
                    .padding(DiffuseTheme.Spacing.regular)
            }
            .diffuseCanvas()
            .navigationTitle(item.entity.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.delete(id: id)
                    dismiss()
                }
            }
        }
        .onChange(of: model.summaries) { _, _ in
            if let summary = model.summaries.first(where: { $0.id == id }) {
                labelDraft = summary.label ?? labelDraft
            }
        }
    }

    private func saveLabel() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = snapshot?.label ?? ""
        guard trimmed != current else { return }
        Task { await model.setLabel(trimmed, for: id) }
    }
}

private struct InspectedEntity: Identifiable, Hashable {
    let entity: SnapshotEntity
    let schema: SectionSchema

    var id: EntityIdentity {
        entity.identity
    }
}

// MARK: - Compare

struct IOSCompareView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(DiffusePreferences.self) private var preferences
    @State private var reportMarkdown = ""

    var body: some View {
        @Bindable var model = model

        ScrollView {
            if let comparison = model.comparison {
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
                        ChangeListView(sections: model.visibleSections)
                    }
                }
                .padding(DiffuseTheme.Spacing.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyStateView(
                    symbol: "arrow.left.arrow.right",
                    title: model.canCompare ? "Pick two snapshots" : "Take another snapshot",
                    message: model.canCompare
                        ? "Long-press a snapshot in the timeline to add it, or compare the two most recent."
                        : "Diffuse needs two snapshots before it can compare anything."
                ) {
                    if model.canCompare {
                        Button("Compare Latest Two") { model.compareLatest() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(DiffuseTheme.Palette.accent)
                    } else {
                        IOSCaptureButton()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 520)
                .padding(DiffuseTheme.Spacing.regular)
            }
        }
        .diffuseCanvas()
        .navigationTitle("Compare")
        .searchable(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            prompt: "Filter changes"
        )
        .toolbar {
            if model.comparison != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: ShareableReport(markdown: reportMarkdown),
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
}

/// Renders the Markdown report lazily so `ShareLink` does not have to await.
struct ShareableReport: Transferable {
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { report in
            Data(report.markdown.utf8)
        }
    }
}

// MARK: - Settings

struct IOSSettingsView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(DiffusePreferences.self) private var preferences
    @State private var ledger: PrivacyLedger?
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            PreferenceSettingsSections(
                preferences: preferences,
                model: model,
                systemEventLabel: "Capture when I open the app"
            )

            Section {
                LabeledContent("Snapshots", value: "\(model.summaries.count)")
                LabeledContent("On disk", value: model.formattedStorage)
                LabeledContent("Capabilities", value: "\(model.availableCapabilityCount)")
            } header: {
                Text("Library")
            }

            Section {
                NavigationLink {
                    IOSCapabilitiesView()
                } label: {
                    Label("Capabilities", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    ScrollView {
                        if let ledger {
                            PrivacyLedgerView(ledger: ledger)
                                .padding(DiffuseTheme.Spacing.regular)
                        } else {
                            ProgressView().padding(.top, 60)
                        }
                    }
                    .diffuseCanvas()
                    .navigationTitle("Privacy")
                    .task { ledger = await model.privacyLedger() }
                } label: {
                    Label("Privacy", systemImage: "lock.shield")
                }
            }

            Section {
                Text("Diffuse takes snapshots when you open it, when you ask, and when iOS grants a background "
                    + "opportunity. It does not run continuously, and does not claim to.")
                    .font(.callout)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    .listRowBackground(Color.clear)
            }

            Section {
                Button("Delete All Snapshots", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .diffuseCanvas()
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete every snapshot?",
            isPresented: $isConfirmingDelete,
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
}

struct IOSCapabilitiesView: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
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
        .task { await model.refreshCapabilities() }
    }
}
