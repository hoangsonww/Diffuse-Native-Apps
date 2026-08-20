import DiffuseModels
import Foundation

/// One hit from a search.
public struct SearchResult: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        case snapshot(SnapshotID)
        case section(SnapshotID, CapabilityID)
        case entity(SnapshotID, CapabilityID, EntityIdentity)
        case change(ChangeID)
    }

    public let id: String
    public let target: Target
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let category: SectionCategory
    public let date: Date

    /// Higher is better. Derived from where the match landed, not from a
    /// language model — an exact match on an entity name beats a substring
    /// match deep in a property value.
    public let score: Double

    public init(
        id: String,
        target: Target,
        title: String,
        subtitle: String,
        symbol: String,
        category: SectionCategory,
        date: Date,
        score: Double
    ) {
        self.id = id
        self.target = target
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.category = category
        self.date = date
        self.score = score
    }
}

/// A generic, capability-agnostic search index.
///
/// The index knows about snapshots, sections, entities and properties — the
/// four structural concepts every capability shares. It has never heard of Git
/// or Docker, which is exactly why searching for `docker` works the moment a
/// Docker collector is registered, with no search code changes.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let haystack: String
        let title: String
        let subtitle: String
        let symbol: String
        let category: SectionCategory
        let date: Date
        let target: SearchResult.Target
        let id: String
        let baseScore: Double
    }

    private let entries: [Entry]

    public init(snapshots: [Snapshot]) {
        var entries: [Entry] = []

        for snapshot in snapshots {
            entries.append(
                Entry(
                    haystack: [
                        snapshot.displayName, snapshot.label ?? "", snapshot.note ?? "",
                        snapshot.device.name, snapshot.platform.rawValue,
                    ].joined(separator: " ").lowercased() + " " + snapshot.tags.joined(separator: " ").lowercased(),
                    title: snapshot.displayName,
                    subtitle: snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened),
                    symbol: snapshot.origin.symbol,
                    category: .system,
                    date: snapshot.capturedAt,
                    target: .snapshot(snapshot.id),
                    id: "snapshot:\(snapshot.id.rawValue)",
                    baseScore: 1.0
                )
            )

            for section in snapshot.sections {
                entries.append(
                    Entry(
                        haystack: [
                            section.displayName, section.schema.summary, section.capability.rawValue,
                            section.collector.rawValue,
                        ].joined(separator: " ").lowercased(),
                        title: section.displayName,
                        subtitle: snapshot.displayName,
                        symbol: section.symbol,
                        category: section.category,
                        date: section.collectedAt,
                        target: .section(snapshot.id, section.capability),
                        id: "section:\(snapshot.id.rawValue):\(section.capability.rawValue)",
                        baseScore: 0.9
                    )
                )

                for entity in section.allEntities {
                    let descriptor = section.schema.descriptor(for: entity.kind)
                    entries.append(
                        Entry(
                            haystack: entity.searchText,
                            title: entity.displayName,
                            subtitle: "\(section.displayName) · \(snapshot.displayName)",
                            symbol: descriptor?.symbol ?? section.symbol,
                            category: section.category,
                            date: section.collectedAt,
                            target: .entity(snapshot.id, section.capability, entity.identity),
                            id: "entity:\(snapshot.id.rawValue):\(section.capability.rawValue):\(entity.identity.token)",
                            baseScore: 0.8
                        )
                    )
                }
            }
        }

        self.entries = entries
    }

    public func search(_ query: String, limit: Int = 40) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let terms = needle.split(separator: " ").map(String.init)

        return entries
            .compactMap { entry -> SearchResult? in
                guard let score = score(entry: entry, terms: terms) else { return nil }
                return SearchResult(
                    id: entry.id,
                    target: entry.target,
                    title: entry.title,
                    subtitle: entry.subtitle,
                    symbol: entry.symbol,
                    category: entry.category,
                    date: entry.date,
                    score: score
                )
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                return $0.id < $1.id
            }
            .prefix(limit)
            .map(\.self)
    }

    /// All terms must match. Matching the title, or matching a whole word,
    /// scores higher than an arbitrary substring hit.
    private func score(entry: Entry, terms: [String]) -> Double? {
        var total = entry.baseScore
        let title = entry.title.lowercased()

        for term in terms {
            guard entry.haystack.contains(term) else { return nil }
            if title == term {
                total += 1.0
            } else if title.hasPrefix(term) {
                total += 0.6
            } else if title.contains(term) {
                total += 0.4
            } else if entry.haystack.split(separator: " ").contains(where: { $0 == Substring(term) }) {
                total += 0.2
            }
        }

        return total
    }
}

/// Searches a set of changes rather than snapshots. Used by the comparison
/// screen's filter field.
public struct ChangeSearchIndex: Sendable {
    private let changes: [Change]

    public init(changes: [Change]) {
        self.changes = changes
    }

    public func search(_ query: String) -> [Change] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return changes }
        let terms = needle.split(separator: " ").map(String.init)
        return changes.filter { change in
            let haystack = change.searchText
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}
