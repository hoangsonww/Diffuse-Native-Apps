import DiffuseModels
import DiffuseUI
import Foundation
import SwiftUI

/// The sections of the Mac app.
enum MacDestination: String, CaseIterable, Identifiable, Hashable {
    case overview
    case snapshots
    case compare
    case capabilities
    case privacy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .snapshots: "Snapshots"
        case .compare: "Compare"
        case .capabilities: "Capabilities"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .snapshots: "clock.arrow.circlepath"
        case .compare: "arrow.left.arrow.right"
        case .capabilities: "slider.horizontal.3"
        case .privacy: "lock.shield"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .snapshots: "2"
        case .compare: "3"
        case .capabilities: "4"
        case .privacy: "5"
        }
    }
}

struct RootView: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(MacAppEnvironment.self) private var environment
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 212, ideal: 236, max: 280)
        } detail: {
            detail
                .diffuseCanvas()
        }
        .navigationTitle(environment.selectedDestination.title)
        .toolbar { toolbar }
        .diffuseFailureBanner(model)
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] {
                switch raw {
                case "search", "snapshot-detail", "entity-detail":
                    environment.selectedDestination = .snapshots
                case "named-snapshot":
                    environment.selectedDestination = .overview
                    environment.isNamingSnapshot = true
                default:
                    if let screen = MacDestination(rawValue: raw) {
                        environment.selectedDestination = screen
                    }
                }
            }
            if ProcessInfo.processInfo.environment["DIFFUSE_SCREENSHOT"] == "compare" {
                model.compareLatest()
            }
            ScreenshotWriter.writeIfRequested()
        }
        .onChange(of: model.summaries.count) { _, count in
            if count >= 2, environment.selectedDestination == .compare, model.comparisonSelection.isEmpty {
                model.compareLatest()
            }
        }
        .onChange(of: model.comparisonSelection) { _, selection in
            if selection.count == 2, environment.selectedDestination == .snapshots {
                withAnimation(DiffuseTheme.Motion.responsive) { environment.selectedDestination = .compare }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var environment = environment

        return List(selection: $environment.selectedDestination) {
            Section {
                ForEach(MacDestination.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                        .keyboardShortcut(item.shortcut, modifiers: .command)
                }
            }

            Section("Library") {
                LabeledContent("Snapshots", value: "\(model.summaries.count)")
                LabeledContent("Capabilities", value: "\(model.availableCapabilityCount)")
                LabeledContent("On disk", value: model.formattedStorage)
            }
            .font(.caption)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            DiffuseBrandMark()
                .padding(.horizontal, DiffuseTheme.Spacing.regular)
                .padding(.top, DiffuseTheme.Spacing.small)
                .padding(.bottom, DiffuseTheme.Spacing.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            CaptureButton()
                .padding(DiffuseTheme.Spacing.medium)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch environment.selectedDestination {
        case .overview:
            OverviewView(onShowComparison: { environment.selectedDestination = .compare })
        case .snapshots:
            SnapshotsView()
        case .compare:
            CompareView()
        case .capabilities:
            CapabilitiesView()
        case .privacy:
            PrivacyView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.phase.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload the snapshot library")

            Button {
                Task { await model.capture() }
            } label: {
                Label("Take Snapshot", systemImage: "camera.aperture")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(model.phase.isBusy)
            .help("Capture the current state of this Mac (⌘N)")
        }
    }
}

/// The primary action, repeated in the sidebar so it is always reachable.
struct CaptureButton: View {
    @Environment(DiffuseModel.self) private var model

    var body: some View {
        Button {
            Task { await model.capture() }
        } label: {
            HStack(spacing: DiffuseTheme.Spacing.small) {
                Image(systemName: model.phase == .capturing ? "hourglass" : "camera.aperture")
                    .symbolEffect(.pulse, isActive: model.phase == .capturing)
                Text(model.phase == .capturing ? "Capturing…" : "Take Snapshot")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(DiffuseTheme.Palette.accent)
        .disabled(model.phase.isBusy)
    }
}

// MARK: - Menu commands

struct DiffuseCommands: Commands {
    let environment: MacAppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Take Snapshot") {
                Task { await environment.model.capture() }
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Take Labelled Snapshot…") {
                environment.isNamingSnapshot = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Compare Latest Two") {
                environment.model.compareLatest()
                environment.selectedDestination = .compare
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!environment.model.canCompare)

            Button("Copy Comparison as Markdown") {
                Task {
                    guard let report = await environment.model.markdownReport(
                        redaction: environment.settings.redaction
                    ) else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(environment.model.comparison == nil)
        }

        CommandGroup(replacing: .help) {
            Link("Diffuse on GitHub", destination: URL(string: "https://github.com/hoangsonww/Diffuse")!)
        }
    }
}
