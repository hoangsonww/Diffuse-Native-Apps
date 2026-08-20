import BackgroundTasks
import DiffuseCollectors
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI

@main
struct DiffuseiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = IOSAppEnvironment(platform: .iOS)

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environment(environment.model)
                .environment(environment.preferences)
                .environment(environment)
                .task { await environment.start() }
                .diffuseCanvas()
                .diffuseWindowBackground()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            environment.scheduleBackgroundRefresh()
        }
        .backgroundTask(.appRefresh(IOSAppEnvironment.backgroundTaskIdentifier)) {
            await environment.performBackgroundCapture()
        }
    }
}

/// Owns the iOS app's service graph and its background scheduling.
///
/// iOS does not let an app run continuously, so Diffuse does not pretend it
/// can. It takes snapshots when you open it, when you ask, and when the system
/// hands it a background opportunity — and it says so, rather than implying a
/// daemon that is not there.
@MainActor
@Observable
final class IOSAppEnvironment {
    static let backgroundTaskIdentifier = "com.diffuse.ios.snapshot"

    let platform: Platform
    private(set) var model: DiffuseModel
    let preferences: DiffusePreferences
    private let defaults = UserDefaults.standard

    init(platform: Platform) {
        self.platform = platform
        preferences = DiffusePreferences()

        let installIdentifier: String
        if let existing = defaults.string(forKey: "diffuse.installIdentifier") {
            installIdentifier = existing
        } else {
            installIdentifier = UUID().uuidString
            defaults.set(installIdentifier, forKey: "diffuse.installIdentifier")
        }

        let service = IOSCapabilityRegistry.makeService(
            storeDirectory: FileSnapshotStore.defaultDirectory(),
            installIdentifier: installIdentifier,
            platform: platform,
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
        ChangeCountStore.iOS.publish(from: model)
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
        ChangeCountStore.iOS.publish(from: model)
        scheduleBackgroundRefresh()
    }
}
