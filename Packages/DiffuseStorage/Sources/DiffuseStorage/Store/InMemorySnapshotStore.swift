import DiffuseModels
import Foundation

/// A store that keeps everything in memory.
///
/// Used by tests, by previews, and by the CLI when it is asked to diff two
/// files without touching the user's library.
public actor InMemorySnapshotStore: SnapshotStore {
    private var storage: [SnapshotID: Snapshot] = [:]

    public init(snapshots: [Snapshot] = []) {
        for snapshot in snapshots {
            storage[snapshot.id] = snapshot
        }
    }

    public func save(_ snapshot: Snapshot) throws {
        guard storage[snapshot.id] == nil else {
            throw StorageError.alreadyExists(snapshot.id)
        }
        storage[snapshot.id] = snapshot
    }

    public func snapshot(id: SnapshotID) -> Snapshot? {
        storage[id]
    }

    public func snapshots(matching query: SnapshotQuery) -> [Snapshot] {
        query
            .apply(to: storage.values.map(SnapshotSummary.init))
            .compactMap { storage[$0.id] }
    }

    public func summaries(matching query: SnapshotQuery) -> [SnapshotSummary] {
        query.apply(to: storage.values.map(SnapshotSummary.init))
    }

    public func annotate(id: SnapshotID, with annotation: SnapshotAnnotation) throws {
        guard var snapshot = storage[id] else {
            throw StorageError.notFound(id)
        }
        if let label = annotation.label {
            snapshot.label = label
        }
        if let note = annotation.note {
            snapshot.note = note
        }
        if let isPinned = annotation.isPinned {
            snapshot.isPinned = isPinned
        }
        if let tags = annotation.tags {
            snapshot.tags = tags
        }
        storage[id] = snapshot
    }

    public func delete(id: SnapshotID) throws {
        guard storage.removeValue(forKey: id) != nil else {
            throw StorageError.notFound(id)
        }
    }

    public func deleteAll() {
        storage.removeAll()
    }

    public func count() -> Int {
        storage.count
    }

    public func storageSize() throws -> Int64 {
        let encoder = SnapshotCoding.makeEncoder(prettyPrinted: false)
        return try storage.values.reduce(into: Int64(0)) { total, snapshot in
            try total += Int64(encoder.encode(SnapshotEnvelope(snapshot)).count)
        }
    }
}
