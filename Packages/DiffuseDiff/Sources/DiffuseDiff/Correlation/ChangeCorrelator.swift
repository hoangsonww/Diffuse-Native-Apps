import DiffuseModels
import Foundation

/// Groups changes that happened close together in time.
///
/// This is deterministic interval clustering, not inference. Changes are sorted
/// by observation time and split wherever the gap between consecutive changes
/// exceeds the window. No model, no guessing, no hidden state — the same input
/// always produces the same clusters, which is what makes it testable.
public enum ChangeCorrelator {
    public static func cluster(
        _ changes: [Change],
        window: TimeInterval,
        minimumSize: Int
    ) -> [ChangeCluster] {
        guard window > 0, minimumSize > 0, !changes.isEmpty else { return [] }

        let ordered = changes.sorted {
            if $0.observedAt != $1.observedAt {
                return $0.observedAt < $1.observedAt
            }
            return $0.id < $1.id
        }

        var groups: [[Change]] = []
        var current: [Change] = []

        for change in ordered {
            guard let last = current.last else {
                current = [change]
                continue
            }
            if change.observedAt.timeIntervalSince(last.observedAt) <= window {
                current.append(change)
            } else {
                groups.append(current)
                current = [change]
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        return groups
            .filter { $0.count >= minimumSize }
            .map { group in
                let start = group.first?.observedAt ?? Date(timeIntervalSince1970: 0)
                let end = group.last?.observedAt ?? start
                var seen = Set<CapabilityID>()
                var capabilities: [CapabilityID] = []
                for change in group where seen.insert(change.capability).inserted {
                    capabilities.append(change.capability)
                }
                return ChangeCluster(
                    id: clusterID(start: start, end: end, count: group.count),
                    start: start,
                    end: end,
                    changeIDs: group.map(\.id).sorted(),
                    peakSeverity: group.map(\.severity).max() ?? .informational,
                    capabilities: capabilities
                )
            }
    }

    /// Deterministic, human-inspectable cluster identifier.
    private static func clusterID(start: Date, end: Date, count: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "cluster:\(formatter.string(from: start))..\(formatter.string(from: end))#\(count)"
    }
}
