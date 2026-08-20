import DiffuseCollectors
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import SwiftUI
import WatchKit

@main
struct DiffuseWatchApp: App {
    @State private var environment = WatchAppEnvironment()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(environment.model)
                .environment(environment.preferences)
                .task { await environment.start() }
                .diffuseWindowBackground()
        }
        .backgroundTask(.appRefresh) { _ in
            await environment.performBackgroundCapture()
        }
    }
}

/// The Watch app is standalone: it snapshots the watch itself and needs no
/// paired iPhone app.
///
/// Its capability set is four items, not twelve, and its retention window is a
/// month rather than a quarter. Pretending a watch can enumerate applications
/// or developer tools would be dishonest, and pretending it has room for a
/// year of history would be worse.
@MainActor
@Observable
final class WatchAppEnvironment {
    private(set) var model: DiffuseModel
    let preferences: DiffusePreferences
    private let defaults = UserDefaults.standard

    init() {
        preferences = DiffusePreferences()
        if UserDefaults.standard.object(forKey: DiffusePreferences.Key.retentionDays) == nil {
            preferences.retentionDays = 30
        }
        let installIdentifier: String
        if let existing = defaults.string(forKey: "diffuse.installIdentifier") {
            installIdentifier = existing
        } else {
            installIdentifier = UUID().uuidString
            defaults.set(installIdentifier, forKey: "diffuse.installIdentifier")
        }

        let service = WatchCapabilityRegistry.makeService(
            storeDirectory: FileSnapshotStore.defaultDirectory(),
            installIdentifier: installIdentifier,
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
                .flatMap(SemanticVersion.init) ?? "1.0.0"
        )
        model = DiffuseModel(service: service)
    }

    func start() async {
        await model.setRetentionPolicy(preferences.retentionPolicy)
        await model.load()
        await model.refreshCapabilities()
        await WatchComplicationBridge.publish(model: model)

        let decision = SnapshotScheduler.decide(
            schedule: preferences.schedule,
            lastCapture: model.latestSummary?.capturedAt,
            now: Date(),
            systemEvent: preferences.capturesOnSystemEvents
        )
        if decision.shouldCapture {
            await model.capture(origin: .triggered, skipIfUnchanged: preferences.skipsWhenUnchanged)
            await WatchComplicationBridge.publish(model: model)
        }
        scheduleBackgroundRefresh()
    }

    func performBackgroundCapture() async {
        await model.capture(
            origin: .scheduled,
            isBackground: true,
            skipIfUnchanged: preferences.skipsWhenUnchanged
        )
        await WatchComplicationBridge.publish(model: model)
        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        guard preferences.cadence != .off else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: preferences.cadence.interval ?? 4 * 3600),
            userInfo: nil
        ) { _ in }
    }
}
