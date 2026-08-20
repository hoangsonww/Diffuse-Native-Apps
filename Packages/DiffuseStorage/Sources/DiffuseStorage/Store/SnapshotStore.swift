import DiffuseModels
import Foundation

/// A lightweight timeline row.
///
/// Timelines can span thousands of snapshots; decoding every one of them to
/// draw a list would be wasteful, so the store maintains summaries alongside
/// the full records.
public struct SnapshotSummary: Sendable, Hashable, Codable, Identifiable {
    public let id: SnapshotID
    public let capturedAt: Date
    public let platform: Platform
    public let origin: SnapshotOrigin
    public var label: String?
    public var isPinned: Bool
    public var tags: Set<String>
    public let sectionCount: Int
    public let entityCount: Int
    public let deviceName: String

    /// Sections that reported a problem, so the timeline can flag them without
    /// loading the snapshot.
    public let problemCount: Int

    public init(
        id: SnapshotID,
        capturedAt: Date,
        platform: Platform,
        origin: SnapshotOrigin,
        label: String?,
        isPinned: Bool,
        tags: Set<String>,
        sectionCount: Int,
        entityCount: Int,
        deviceName: String,
        problemCount: Int
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.platform = platform
        self.origin = origin
        self.label = label
        self.isPinned = isPinned
        self.tags = tags
        self.sectionCount = sectionCount
        self.entityCount = entityCount
        self.deviceName = deviceName
        self.problemCount = problemCount
    }

    public init(_ snapshot: Snapshot) {
        self.init(
            id: snapshot.id,
            capturedAt: snapshot.capturedAt,
            platform: snapshot.platform,
            origin: snapshot.origin,
            label: snapshot.label,
            isPinned: snapshot.isPinned,
            tags: snapshot.tags,
            sectionCount: snapshot.sections.count,
            entityCount: snapshot.entityCount,
            deviceName: snapshot.device.name,
            problemCount: snapshot.problemSections.count
        )
    }

    public var displayName: String {
        if let label, !label.isEmpty {
            return label
        }
        return capturedAt.formatted(date: .omitted, time: .shortened)
    }
}

/// Filtering and ordering for a timeline query.
public struct SnapshotQuery: Sendable, Hashable {
    public enum SortOrder: Sendable, Hashable {
        case newestFirst
        case oldestFirst
    }

    public var range: ClosedRange<Date>?
    public var platforms: Set<Platform>?
    public var origins: Set<SnapshotOrigin>?
    public var tags: Set<String>
    public var pinnedOnly: Bool
    public var searchText: String?
    public var sort: SortOrder
    public var limit: Int?
    public var offset: Int

    public init(
        range: ClosedRange<Date>? = nil,
        platforms: Set<Platform>? = nil,
        origins: Set<SnapshotOrigin>? = nil,
        tags: Set<String> = [],
        pinnedOnly: Bool = false,
        searchText: String? = nil,
        sort: SortOrder = .newestFirst,
        limit: Int? = nil,
        offset: Int = 0
    ) {
        self.range = range
        self.platforms = platforms
        self.origins = origins
        self.tags = tags
        self.pinnedOnly = pinnedOnly
        self.searchText = searchText
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    public static let all = SnapshotQuery()

    public static func recent(_ count: Int) -> SnapshotQuery {
        SnapshotQuery(limit: count)
    }

    /// Applies the query to an in-memory list. Shared by every store
    /// implementation so filtering semantics cannot drift between them.
    public func apply(to summaries: [SnapshotSummary]) -> [SnapshotSummary] {
        var result = summaries.filter { summary in
            if let range, !range.contains(summary.capturedAt) {
                return false
            }
            if let platforms, !platforms.contains(summary.platform) {
                return false
            }
            if let origins, !origins.contains(summary.origin) {
                return false
            }
            if pinnedOnly, !summary.isPinned {
                return false
            }
            if !tags.isEmpty, tags.isDisjoint(with: summary.tags) {
                return false
            }
            if let searchText, !searchText.isEmpty {
                let haystack = [summary.displayName, summary.label ?? "", summary.deviceName]
                    .joined(separator: " ")
                    .lowercased()
                let needle = searchText.lowercased()
                if !haystack.contains(needle), !summary.tags.contains(where: { $0.lowercased().contains(needle) }) {
                    return false
                }
            }
            return true
        }

        // Ties are broken by identifier so paging is stable when two snapshots
        // share a timestamp.
        result.sort { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return sort == .newestFirst
                    ? lhs.capturedAt > rhs.capturedAt
                    : lhs.capturedAt < rhs.capturedAt
            }
            return lhs.id < rhs.id
        }

        if offset > 0 {
            result = Array(result.dropFirst(offset))
        }
        if let limit {
            result = Array(result.prefix(limit))
        }
        return result
    }
}

/// User-editable annotations. Kept separate from `Snapshot` mutation so the
/// immutability rule stays enforceable: observed state is never rewritten,
/// only the labels a person attaches to it.
public struct SnapshotAnnotation: Sendable, Hashable, Codable {
    public var label: String?
    public var note: String?
    public var isPinned: Bool?
    public var tags: Set<String>?

    public init(label: String? = nil, note: String? = nil, isPinned: Bool? = nil, tags: Set<String>? = nil) {
        self.label = label
        self.note = note
        self.isPinned = isPinned
        self.tags = tags
    }
}

public enum StorageError: Error, Sendable, Hashable, LocalizedError {
    case notFound(SnapshotID)
    case alreadyExists(SnapshotID)
    case corrupted(String)
    case unsupportedSchema(SchemaVersion)
    case quotaExceeded(bytes: Int64, limit: Int64)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(id): "Snapshot \(id.shortValue) was not found."
        case let .alreadyExists(id): "Snapshot \(id.shortValue) already exists."
        case let .corrupted(detail): "A snapshot file is unreadable: \(detail)"
        case let .unsupportedSchema(version): "Snapshot schema \(version) is not supported."
        case let .quotaExceeded(bytes, limit):
            "Storage is full (\(bytes.formatted(.byteCount(style: .file))) of \(limit.formatted(.byteCount(style: .file))))."
        case let .io(detail): "Could not update the snapshot library: \(detail)"
        }
    }
}

/// Persistence for snapshots.
///
/// The core packages depend only on this protocol; each app supplies a
/// concrete implementation. That is what lets the CLI use flat files, the
/// tests use memory, and the apps use their own on-disk layout without any of
/// them leaking into the domain.
public protocol SnapshotStore: Sendable {
    func save(_ snapshot: Snapshot) async throws
    func snapshot(id: SnapshotID) async throws -> Snapshot?
    func snapshots(matching query: SnapshotQuery) async throws -> [Snapshot]
    func summaries(matching query: SnapshotQuery) async throws -> [SnapshotSummary]
    func annotate(id: SnapshotID, with annotation: SnapshotAnnotation) async throws
    func delete(id: SnapshotID) async throws
    func deleteAll() async throws
    func count() async throws -> Int

    /// Total bytes on disk, used by retention and the storage settings screen.
    func storageSize() async throws -> Int64
}

public extension SnapshotStore {
    /// The most recent snapshot, if any.
    func latest() async throws -> Snapshot? {
        try await snapshots(matching: SnapshotQuery(limit: 1)).first
    }

    /// The two most recent snapshots, oldest first, ready to hand to the diff
    /// engine. Returns `nil` until there is something to compare.
    func latestPair() async throws -> (base: Snapshot, target: Snapshot)? {
        let recent = try await snapshots(matching: SnapshotQuery(limit: 2))
        guard recent.count == 2 else { return nil }
        return (base: recent[1], target: recent[0])
    }

    func allSummaries() async throws -> [SnapshotSummary] {
        try await summaries(matching: .all)
    }

    func require(id: SnapshotID) async throws -> Snapshot {
        guard let snapshot = try await snapshot(id: id) else {
            throw StorageError.notFound(id)
        }
        return snapshot
    }
}
