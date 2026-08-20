import DiffuseCollectors
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI

@main
struct DiffuseMacApp: App {
    @State private var environment = MacAppEnvironment()

    var body: some Scene {
        WindowGroup(id: "workspace") {
            RootView()
                .environment(environment.model)
                .environment(environment.settings)
                .environment(environment)
                .task { await environment.start() }
                .frame(minWidth: 980, minHeight: 680)
                .diffuseCanvas()
                .diffuseWindowBackground()
                .sheet(isPresented: $environment.isNamingSnapshot) {
                    NamedSnapshotSheet()
                        .environment(environment.model)
                        .environment(environment)
                }
                .onOpenURL { url in
                    Task { await environment.importFromURL(url) }
                }
        }
        .defaultSize(width: 1280, height: 840)
        .commands { DiffuseCommands(environment: environment) }

        Settings {
            SettingsView()
                .environment(environment.model)
                .environment(environment.settings)
                .frame(width: 560, height: 460)
        }

        // The menu bar extra is deliberately a small convenience — take a
        // snapshot, see the count, open the app — rather than the product
        // itself. Diffuse is a real application, not a menu bar utility.
        MenuBarExtra {
            MenuBarContent()
                .environment(environment.model)
                .diffuseFailureBanner(environment.model)
        } label: {
            MenuBarLabel()
                .environment(environment.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app's long-lived objects and wires them together once.
@MainActor
@Observable
final class MacAppEnvironment {
    let settings: MacSettings
    private(set) var model: DiffuseModel
    private var scheduler: SnapshotSchedulerDriver?
    var isNamingSnapshot = false
    var selectedDestination: MacDestination = .overview

    init() {
        let settings = MacSettings()
        self.settings = settings

        let service = MacCapabilityRegistry.makeService(
            storeDirectory: FileSnapshotStore.defaultDirectory(),
            installIdentifier: settings.installIdentifier,
            watchedRepositoryPaths: { [list = settings.repositoryWatchList] in list.current() },
            appVersion: Self.bundleVersion
        )
        model = DiffuseModel(service: service)
    }

    func start() async {
        await model.setRetentionPolicy(settings.retentionPolicy)
        await model.load()
        await model.refreshCapabilities()

        let driver = SnapshotSchedulerDriver(model: model, settings: settings)
        scheduler = driver
        await driver.start()
    }

    func importFromURL(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            _ = await model.importSnapshot(from: data)
        } catch {
            model.reportFailure(error.localizedDescription)
        }
    }

    static var bundleVersion: SemanticVersion {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(SemanticVersion.init) ?? "1.0.0"
    }
}

/// Asks for a name before capturing, so a snapshot taken around a known event
/// is findable later instead of living as an anonymous timestamp.
struct NamedSnapshotSheet: View {
    @Environment(DiffuseModel.self) private var model
    @Environment(MacAppEnvironment.self) private var environment
    @State private var label = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
            Text("Name this snapshot")
                .font(.title3.weight(.semibold))
            Text(
                "A name is kept forever by retention, so use it for the moments you might want to compare later — before an upgrade, after a toolchain change."
            )
            .font(.callout)
            .foregroundStyle(DiffuseTheme.Palette.subtleText)
            .fixedSize(horizontal: false, vertical: true)

            TextField("For example, Before macOS update", text: $label)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { Task { await capture() } }

            HStack {
                Spacer()
                Button("Cancel") { environment.isNamingSnapshot = false }
                    .keyboardShortcut(.cancelAction)
                Button("Take Snapshot") { Task { await capture() } }
                    .buttonStyle(.borderedProminent)
                    .tint(DiffuseTheme.Palette.accent)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.phase.isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DiffuseTheme.Spacing.large)
        .frame(width: 420)
        .background(DiffuseTheme.Palette.canvas)
        .onAppear { isFocused = true }
    }

    private func capture() async {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        environment.isNamingSnapshot = false
        await model.capture(label: trimmed)
    }
}
