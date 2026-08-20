import DiffuseModels
import Foundation

/// A snapshot library backed by one JSON file per snapshot plus an index.
///
/// Chosen over a database deliberately. Snapshots are immutable append-only
/// documents, the access pattern is "list summaries, then open one", and a
/// directory of readable JSON means a user can inspect, back up, copy or
/// delete their own data with the tools they already have. The index exists
/// only as a cache: it can be deleted and is rebuilt from the files.
public actor FileSnapshotStore: SnapshotStore {
    public let directory: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var index: [SnapshotID: SnapshotSummary]
    private var isIndexLoaded = false

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    private var snapshotsDirectory: URL {
        directory.appendingPathComponent("snapshots", isDirectory: true)
    }

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        encoder = SnapshotCoding.makeEncoder(prettyPrinted: true)
        decoder = SnapshotCoding.makeDecoder()
        index = [:]
    }

    /// The default library location for an app: an application-support
    /// subdirectory that participates in the normal backup rules.
    public static func defaultDirectory(appName: String = "Diffuse") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    // MARK: - SnapshotStore

    public func save(_ snapshot: Snapshot) throws {
        try loadIndexIfNeeded()
        let url = fileURL(for: snapshot.id)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw StorageError.alreadyExists(snapshot.id)
        }
        try writeSnapshot(snapshot, to: url)
        index[snapshot.id] = SnapshotSummary(snapshot)
        try writeIndex()
    }

    public func snapshot(id: SnapshotID) throws -> Snapshot? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try SnapshotCoding.decodeSnapshot(Data(contentsOf: url))
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.io(String(describing: error))
        }
    }

    public func snapshots(matching query: SnapshotQuery) throws -> [Snapshot] {
        try summaries(matching: query).compactMap { summary in
            do {
                return try snapshot(id: summary.id)
            } catch {
                return nil
            }
        }
    }

    public func summaries(matching query: SnapshotQuery) throws -> [SnapshotSummary] {
        try loadIndexIfNeeded()
        return query.apply(to: Array(index.values))
    }

    public func annotate(id: SnapshotID, with annotation: SnapshotAnnotation) throws {
        try loadIndexIfNeeded()
        guard var snapshot = try snapshot(id: id) else {
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

        try writeSnapshot(snapshot, to: fileURL(for: id))
        index[id] = SnapshotSummary(snapshot)
        try writeIndex()
    }

    public func delete(id: SnapshotID) throws {
        try loadIndexIfNeeded()
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.notFound(id)
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw StorageError.io(String(describing: error))
        }
        index.removeValue(forKey: id)
        try writeIndex()
    }

    public func deleteAll() throws {
        if fileManager.fileExists(atPath: snapshotsDirectory.path) {
            do {
                try fileManager.removeItem(at: snapshotsDirectory)
            } catch {
                throw StorageError.io(String(describing: error))
            }
        }
        index.removeAll()
        try writeIndex()
        try createDirectoriesIfNeeded()
    }

    public func count() throws -> Int {
        try loadIndexIfNeeded()
        return index.count
    }

    public func storageSize() throws -> Int64 {
        try loadIndexIfNeeded()
        guard let enumerator = fileManager.enumerator(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Index maintenance

    /// Rebuilds the index by reading every snapshot file. Called on first
    /// access when the index is missing or unreadable, and available to the
    /// CLI as a repair step.
    @discardableResult
    public func rebuildIndex() throws -> Int {
        try createDirectoriesIfNeeded()
        var rebuilt: [SnapshotID: SnapshotSummary] = [:]

        let urls = (try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let snapshot = try? SnapshotCoding.decodeSnapshot(data)
            else { continue }
            rebuilt[snapshot.id] = SnapshotSummary(snapshot)
        }

        index = rebuilt
        isIndexLoaded = true
        try writeIndex()
        return rebuilt.count
    }

    private func loadIndexIfNeeded() throws {
        guard !isIndexLoaded else { return }
        try createDirectoriesIfNeeded()

        guard
            let data = try? Data(contentsOf: indexURL),
            let stored = try? decoder.decode([SnapshotSummary].self, from: data)
        else {
            try rebuildIndex()
            return
        }

        index = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
        isIndexLoaded = true
    }

    private func writeIndex() throws {
        try createDirectoriesIfNeeded()
        let ordered = index.values.sorted { $0.capturedAt > $1.capturedAt }
        do {
            try atomicWrite(encoder.encode(ordered), to: indexURL)
        } catch {
            throw StorageError.io(String(describing: error))
        }
    }

    private func writeSnapshot(_ snapshot: Snapshot, to url: URL) throws {
        try createDirectoriesIfNeeded()
        do {
            try atomicWrite(encoder.encode(SnapshotEnvelope(snapshot)), to: url)
        } catch {
            throw StorageError.io(String(describing: error))
        }
    }

    /// Writes via a temporary file and an atomic replace so an interrupted
    /// write can never leave a half-written snapshot behind.
    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: url)
        }
    }

    private func createDirectoriesIfNeeded() throws {
        for url in [directory, snapshotsDirectory] where !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw StorageError.io(String(describing: error))
            }
        }
    }

    private func fileURL(for id: SnapshotID) -> URL {
        snapshotsDirectory.appendingPathComponent("\(sanitize(id.rawValue)).json")
    }

    private func sanitize(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "-"
        }
        .reduce(into: "") { $0.append($1) }
    }
}
