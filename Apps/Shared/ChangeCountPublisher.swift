#if canImport(WidgetKit)
import DiffuseUI
import Foundation
import WidgetKit

extension ChangeCountStore {
    /// Publishes the current change count and asks every widget to redraw.
    ///
    /// Called after every capture rather than on a timer: the number only
    /// changes when a snapshot is taken, so a scheduled refresh would be
    /// redrawing the same value over and over.
    @MainActor
    func publish(from model: DiffuseModel) {
        write(
            ChangeCountSummary(
                changeCount: model.overview?.summary.totalChanges ?? 0,
                peakSeverity: model.overview?.summary.peakSeverity,
                capturedAt: model.latestSummary?.capturedAt
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchComplicationBridge {
    @MainActor
    static func publish(model: DiffuseModel) async {
        ChangeCountStore.watch.publish(from: model)
    }
}
#endif
