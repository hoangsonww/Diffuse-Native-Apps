import AppKit
import DiffuseCore
import DiffuseModels
import DiffuseUI
import Foundation

/// Turns `SnapshotScheduler`'s decisions into actual captures on macOS.
///
/// The decision logic lives in `DiffuseCore` and is unit tested; this type only
/// supplies the platform's sense of time and its wake notifications. Each
/// platform has a different driver for the same shared brain.
@MainActor
final class SnapshotSchedulerDriver {
    private let model: DiffuseModel
    private let settings: MacSettings
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    /// How often the scheduler is *consulted*. Deliberately much more frequent
    /// than the shortest cadence so that a laptop asleep through its slot still
    /// captures promptly after waking.
    private let pollInterval: Duration = .seconds(60)

    init(model: DiffuseModel, settings: MacSettings) {
        self.model = model
        self.settings = settings
    }

    func start() async {
        observeSystemEvents()

        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.evaluate(systemEvent: false)
            }
        }
    }

    /// Tears down the poll loop and the workspace observers.
    ///
    /// Explicit rather than in `deinit`: the observers are main-actor state,
    /// and a nonisolated `deinit` cannot touch them safely.
    func stop() {
        timer?.cancel()
        timer = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.evaluate(systemEvent: true) }
            }
            observers.append(observer)
        }
    }

    private func evaluate(systemEvent: Bool) async {
        let decision = SnapshotScheduler.decide(
            schedule: settings.schedule,
            lastCapture: model.latestSummary?.capturedAt,
            now: Date(),
            systemEvent: systemEvent
        )

        guard case let .capture(reason) = decision else { return }
        await model.setRetentionPolicy(settings.retentionPolicy)
        await model.capture(
            origin: reason == .systemEvent ? .triggered : .scheduled,
            skipIfUnchanged: settings.schedule.skipsWhenUnchanged
        )
    }
}
