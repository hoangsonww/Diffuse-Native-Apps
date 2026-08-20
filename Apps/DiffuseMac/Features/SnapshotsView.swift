import AppKit
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI
import UniformTypeIdentifiers

/// The snapshot timeline, and the detail of whichever one is selected.
struct SnapshotsView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(MacSettings.self) private var settings
    @State private var selected: SnapshotID?
    @State private var loadedSnapshot: Snapshot?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: SnapshotDocument?
    @State private var pendingDelete: SnapshotID?
    @State private var focusEntity: EntityIdentity?

    var body: some View {
        HSplitView {
            timeline
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
            detail
                .frame(minWidth: 420)
        }
        .background(DiffuseTheme.Palette.canvas)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a snapshot exported from another device")

                Button {
                    Task { await exportSelected() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selected == nil)
                .help("Export the selected snapshot as JSON")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .diffuseSnapshot]
        ) { result in
            Task { await importFile(result) }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                model.reportFailure(error.localizedDescription)
            }
        }
        .task(id: selected) { await loadSelected() }
        .onAppear {
            if selected == nil {
                selected = model.summaries.first?.id
            }
        }
        .onChange(of: model.summaries.count) { _, _ in
            if selected == nil {
                selected = model.summaries.first?.id
            }
        }
        .searchable(text: Binding(
            get: { model.libraryQuery },
            set: { query in
                Task { await model.searchLibrary(query) }
            }
        ), prompt: "Search snapshots, apps, networks…")
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
                    if selected == pendingDelete {
                        selected = nil
                    }
                    self.pendingDelete = nil
                }
            }
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
                if model.isSearchingLibrary {
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        LibrarySearchResultsView(results: model.libraryResults) { result in
                            if let id = result.snapshotID {
                                selected = id
                                focusEntity = result.entityIdentity
                            }
                        }
                    }
                } else {
                    if model.canCompare {
                        comparisonHint
                    }

                    SnapshotTimelineView(summaries: model.summaries) { summary in
                        HStack(alignment: .center, spacing: DiffuseTheme.Spacing.small) {
                            Button {
                                if NSEvent.modifierFlags.contains(.command) {
                                    model.toggleComparison(summary.id)
                                } else {
                                    selected = summary.id
                                }
                            } label: {
                                TimelineRow(
                                    summary: summary,
                                    isSelected: selected == summary.id || model.comparisonSelection
                                        .contains(summary.id),
                                    selectionOrder: model.selectionOrder(of: summary.id)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.toggleComparison(summary.id)
                            } label: {
                                Image(systemName: model.comparisonSelection.contains(summary.id)
                                    ? "minus.circle"
                                    : "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(model.comparisonSelection.contains(summary.id)
                                ? "Remove from comparison"
                                : "Add to comparison")
                            .accessibilityLabel(model.comparisonSelection.contains(summary.id)
                                ? "Remove from comparison"
                                : "Add to comparison")
                        }
                        .contextMenu { contextMenu(for: summary) }
                    }
                }
            }
            .padding(DiffuseTheme.Spacing.regular)
        }
        .background(DiffuseTheme.Palette.canvas)
        .overlay {
            if model.phase == .loading, !model.hasSnapshots {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diffuseCanvas()
            } else if !model.hasSnapshots {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No snapshots",
                    message: "Press ⌘N to capture the current state of this Mac."
                )
                .diffuseCanvas()
            }
        }
    }

    private var comparisonHint: some View {
        Card(padding: DiffuseTheme.Spacing.medium) {
            HStack(spacing: DiffuseTheme.Spacing.small) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(DiffuseTheme.Palette.accent)
                Text(model.comparisonSelection.isEmpty
                    ? "Click to inspect. Use + or ⌘-click to add to a comparison."
                    : "\(model.comparisonSelection.count) of 2 selected.")
                    .font(.caption)
                Spacer()
                if !model.comparisonSelection.isEmpty {
                    Button("Clear") { model.clearComparison() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for summary: SnapshotSummary) -> some View {
        Button(model.comparisonSelection.contains(summary.id) ? "Remove from Comparison" : "Add to Comparison") {
            model.toggleComparison(summary.id)
        }
        Button(summary.isPinned ? "Unpin" : "Pin") {
            Task { await model.setPinned(!summary.isPinned, for: summary.id) }
        }
        Divider()
        Button("Delete", role: .destructive) {
            pendingDelete = summary.id
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let snapshot = loadedSnapshot {
            SnapshotDetailView(snapshot: snapshot, focusEntity: focusEntity)
        } else if selected != nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(
                symbol: "sidebar.right",
                title: "Select a snapshot",
                message: "Choose a snapshot on the left to see everything it recorded."
            )
            .diffuseCanvas()
        }
    }

    private func loadSelected() async {
        guard let selected else {
            loadedSnapshot = nil
            return
        }
        loadedSnapshot = await model.snapshot(id: selected)
    }

    private func exportSelected() async {
        guard let selected,
              let data = await model.exportSnapshot(id: selected, redaction: settings.redaction) else { return }
        exportDocument = SnapshotDocument(data: data)
        isExporting = true
    }

    private var exportFilename: String {
        guard let loadedSnapshot else { return "snapshot" }
        return "diffuse-\(loadedSnapshot.id.shortValue)"
    }

    private func importFile(_ result: Result<URL, Error>) async {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                model.reportFailure("Could not access the selected file.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                _ = try await model.importSnapshot(from: Data(contentsOf: url))
            } catch {
                model.reportFailure(error.localizedDescription)
            }
        case let .failure(error):
            model.reportFailure(error.localizedDescription)
        }
    }
}

/// One snapshot's full contents, rendered entirely from its own schema.
struct SnapshotDetailView: View {
    let snapshot: Snapshot
    var focusEntity: EntityIdentity?
    @Environment(DiffuseModel.self) private var model
    @State private var selectedEntity: SnapshotEntity?
    @State private var selectedSchema: SectionSchema?
    @State private var labelDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
                header

                ForEach(snapshot.orderedSections) { section in
                    SnapshotSectionView(section: section) { entity in
                        selectedEntity = entity
                        selectedSchema = section.schema
                    }
                }
            }
            .padding(DiffuseTheme.Spacing.large)
        }
        .background(DiffuseTheme.Palette.canvas)
        .onAppear {
            labelDraft = snapshot.label ?? ""
            revealFocus()
        }
        .onChange(of: snapshot.id) { _, _ in
            labelDraft = snapshot.label ?? ""
            revealFocus()
        }
        .onChange(of: focusEntity) { _, _ in
            revealFocus()
        }
        .onDisappear { saveLabel() }
        .inspector(isPresented: inspectorPresented) {
            if let selectedEntity, let selectedSchema {
                ScrollView {
                    EntityDetailView(entity: selectedEntity, schema: selectedSchema)
                        .padding(DiffuseTheme.Spacing.regular)
                }
                .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                .toolbar {
                    ToolbarItem {
                        Button("Close") { self.selectedEntity = nil }
                    }
                }
            }
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedEntity != nil },
            set: {
                if !$0 {
                    selectedEntity = nil
                }
            }
        )
    }

    private func saveLabel() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = snapshot.label ?? ""
        guard trimmed != current else { return }
        Task { await model.setLabel(trimmed, for: snapshot.id) }
    }

    private func revealFocus() {
        guard let focusEntity else { return }
        for section in snapshot.orderedSections {
            if let entity = section.allEntities.first(where: { $0.identity == focusEntity }) {
                selectedEntity = entity
                selectedSchema = section.schema
                return
            }
        }
    }

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name this snapshot", text: $labelDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3.weight(.semibold))
                            .onSubmit { saveLabel() }
                        Text(snapshot.capturedAt.formatted(date: .complete, time: .standard))
                            .font(.callout)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                    Spacer()
                    Button {
                        Task { await model.setPinned(!snapshot.isPinned, for: snapshot.id) }
                    } label: {
                        Label(
                            snapshot.isPinned ? "Pinned" : "Pin",
                            systemImage: snapshot.isPinned ? "pin.fill" : "pin"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help("Pinned snapshots are never removed by automatic cleanup")
                }

                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Pill(snapshot.origin.displayName, symbol: snapshot.origin.symbol)
                    Pill(snapshot.platform.rawValue, symbol: snapshot.platform.symbol)
                    Pill("\(snapshot.sections.count) sections", symbol: "square.stack.3d.up")
                    Pill("\(snapshot.entityCount) entities", symbol: "circle.grid.3x3")
                    Pill("schema v\(snapshot.schemaVersion)", symbol: "doc.badge.gearshape")
                }

                if snapshot.hasProblems {
                    Label(
                        "\(snapshot.problemSections.count) section\(snapshot.problemSections.count == 1 ? "" : "s") "
                            + "could not be collected in full",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.notable)
                }
            }
        }
    }
}

/// Wraps exported JSON for `fileExporter`.
struct SnapshotDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .diffuseSnapshot]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let diffuseSnapshot = UTType(exportedAs: "com.diffuse.snapshot")
}
