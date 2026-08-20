import BackgroundTasks
import DiffuseCollectors
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI

@main
struct DiffuseiPadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = IPadAppEnvironment()

    var body: some Scene {
        WindowGroup {
            IPadRootView()
                .environment(environment.model)
                .environment(environment.preferences)
                .task { await environment.start() }
                .diffuseCanvas()
                .diffuseWindowBackground()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            environment.scheduleBackgroundRefresh()
        }
        .backgroundTask(.appRefresh(IPadAppEnvironment.backgroundTaskIdentifier)) {
            await environment.performBackgroundCapture()
        }
    }
}

@MainActor
@Observable
final class IPadAppEnvironment {
    static let backgroundTaskIdentifier = "com.diffuse.ipados.snapshot"

    private(set) var model: DiffuseModel
    let preferences: DiffusePreferences
    private let defaults = UserDefaults.standard

    init() {
        preferences = DiffusePreferences()
        let installIdentifier: String
        if let existing = defaults.string(forKey: "diffuse.installIdentifier") {
            installIdentifier = existing
        } else {
            installIdentifier = UUID().uuidString
            defaults.set(installIdentifier, forKey: "diffuse.installIdentifier")
        }

        // Reported as iPadOS rather than iOS. The two share an SDK but expose
        // different capability sets, and a snapshot should say which device it
        // actually came from.
        let service = IOSCapabilityRegistry.makeService(
            storeDirectory: FileSnapshotStore.defaultDirectory(),
            installIdentifier: installIdentifier,
            platform: .iPadOS,
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
                .flatMap(SemanticVersion.init) ?? "1.0.0"
        )
        model = DiffuseModel(service: service)
    }

    func start() async {
        await model.setRetentionPolicy(preferences.retentionPolicy)
        await model.load()
        await model.refreshCapabilities()

        let decision = SnapshotScheduler.decide(
            schedule: preferences.schedule,
            lastCapture: model.latestSummary?.capturedAt,
            now: Date(),
            systemEvent: preferences.capturesOnSystemEvents
        )
        if decision.shouldCapture {
            await model.capture(origin: .triggered, skipIfUnchanged: preferences.skipsWhenUnchanged)
        }
        ChangeCountStore.iPadOS.publish(from: model)
    }

    func scheduleBackgroundRefresh() {
        guard preferences.cadence != .off else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: preferences.cadence.interval ?? 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    func performBackgroundCapture() async {
        await model.capture(
            origin: .scheduled,
            isBackground: true,
            skipIfUnchanged: preferences.skipsWhenUnchanged
        )
        ChangeCountStore.iPadOS.publish(from: model)
        scheduleBackgroundRefresh()
    }
}
