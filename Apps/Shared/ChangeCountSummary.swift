import DiffuseModels
import Foundation

/// The tiny slice of state a widget or complication needs.
///
/// Extensions run in a separate process with their own container, so the host
/// app publishes a two-field summary into a shared app group after every
/// capture. Keeping the payload this small means the widget never has to
/// decode a snapshot to draw `Δ 3`.
public struct ChangeCountSummary: Codable, Sendable, Equatable {
    public let changeCount: Int
    public let peakSeverity: ChangeSeverity?
    public let capturedAt: Date?

    public init(changeCount: Int, peakSeverity: ChangeSeverity?, capturedAt: Date?) {
        self.changeCount = changeCount
        self.peakSeverity = peakSeverity
        self.capturedAt = capturedAt
    }

    public static let placeholder = ChangeCountSummary(
        changeCount: 3,
        peakSeverity: .significant,
        capturedAt: Date(timeIntervalSince1970: 1_787_130_240)
    )

    public static let empty = ChangeCountSummary(changeCount: 0, peakSeverity: nil, capturedAt: nil)
}

/// Reads and writes a change-count summary for one app group.
///
/// Each platform app has its own group identifier. Without a signed build the
/// container is unavailable, so every read falls back to empty rather than
/// failing — widgets still compile and still preview.
public struct ChangeCountStore: Sendable {
    public let appGroup: String
    private let filename = "change-count.json"

    public init(appGroup: String) {
        self.appGroup = appGroup
    }

    public static let watch = ChangeCountStore(appGroup: "group.com.diffuse.watch")
    public static let iOS = ChangeCountStore(appGroup: "group.com.diffuse.ios")
    public static let iPadOS = ChangeCountStore(appGroup: "group.com.diffuse.ipados")

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    public func write(_ summary: ChangeCountSummary) {
        guard let url = containerURL?.appendingPathComponent(filename) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(summary).write(to: url, options: .atomic)
    }

    public func read() -> ChangeCountSummary {
        guard
            let url = containerURL?.appendingPathComponent(filename),
            let data = try? Data(contentsOf: url)
        else { return .empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ChangeCountSummary.self, from: data)) ?? .empty
    }
}

/// Watch code still refers to the original names.
public typealias ComplicationSummary = ChangeCountSummary

public enum WatchComplicationBridge {
    public static let appGroup = ChangeCountStore.watch.appGroup

    public static func write(_ summary: ComplicationSummary) {
        ChangeCountStore.watch.write(summary)
    }

    public static func read() -> ComplicationSummary {
        ChangeCountStore.watch.read()
    }
}
