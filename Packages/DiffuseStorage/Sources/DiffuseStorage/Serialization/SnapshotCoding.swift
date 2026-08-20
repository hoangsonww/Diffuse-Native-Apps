import DiffuseModels
import Foundation

/// The on-disk and on-the-wire representation of a snapshot.
///
/// Exports are plain JSON with a stable envelope so a snapshot can travel by
/// AirDrop, email or a GitHub issue attachment and still be understood by a
/// different device running a different version of Diffuse.
public enum SnapshotCoding {
    /// File extension used for exported snapshots.
    public static let fileExtension = "diffuse.json"

    /// Sorted keys and ISO-8601 dates with milliseconds.
    ///
    /// Sorted keys make two encodes of the same value byte-identical, which is
    /// what golden fixtures rely on. Fractional seconds matter because plain
    /// `.iso8601` truncates to whole seconds, and a snapshot that changes when
    /// you save and reload it is not much of a record.
    public static func makeEncoder(prettyPrinted: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(iso8601Milliseconds)
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = iso8601Milliseconds.date(from: text) {
                return date.roundedForSnapshot()
            }
            // Tolerate whole-second timestamps from hand-written fixtures.
            if let date = iso8601Seconds.date(from: text) {
                return date.roundedForSnapshot()
            }
            throw try DecodingError.dataCorruptedError(
                in: decoder.singleValueContainer(),
                debugDescription: "Unrecognised date '\(text)'"
            )
        }
        return decoder
    }

    static let iso8601Milliseconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return formatter
    }()

    static let iso8601Seconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()

    // MARK: - Snapshots

    public static func encode(_ snapshot: Snapshot, prettyPrinted: Bool = true) throws -> Data {
        try makeEncoder(prettyPrinted: prettyPrinted).encode(SnapshotEnvelope(snapshot))
    }

    /// Decodes a snapshot, migrating it forward if it was written by an older
    /// build.
    public static func decodeSnapshot(_ data: Data) throws -> Snapshot {
        let decoder = makeDecoder()
        do {
            let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
            return try SnapshotMigrator.migrate(envelope.snapshot, from: envelope.schemaVersion)
        } catch let error as StorageError {
            throw error
        } catch {
            // Tolerate a bare `Snapshot` without the envelope, which is what
            // hand-written fixtures and older exports look like.
            if let snapshot = try? decoder.decode(Snapshot.self, from: data) {
                return try SnapshotMigrator.migrate(snapshot, from: snapshot.schemaVersion)
            }
            throw StorageError.corrupted(String(describing: error))
        }
    }

    // MARK: - Diffs

    public static func encode(_ diff: DiffResult, prettyPrinted: Bool = true) throws -> Data {
        try makeEncoder(prettyPrinted: prettyPrinted).encode(DiffEnvelope(diff))
    }

    public static func decodeDiff(_ data: Data) throws -> DiffResult {
        let decoder = makeDecoder()
        if let envelope = try? decoder.decode(DiffEnvelope.self, from: data) {
            return envelope.diff
        }
        do {
            return try decoder.decode(DiffResult.self, from: data)
        } catch {
            throw StorageError.corrupted(String(describing: error))
        }
    }
}

/// The export envelope. The `format` and `schemaVersion` fields sit outside the
/// payload so a reader can decide how to interpret it before decoding it.
public struct SnapshotEnvelope: Sendable, Codable {
    public let format: String
    public let schemaVersion: SchemaVersion
    public let exportedAt: Date
    public let snapshot: Snapshot

    public init(_ snapshot: Snapshot, exportedAt: Date? = nil) {
        format = "diffuse.snapshot"
        schemaVersion = snapshot.schemaVersion
        // Defaults to the capture time so that exporting the same snapshot
        // twice produces identical bytes.
        self.exportedAt = exportedAt ?? snapshot.capturedAt
        self.snapshot = snapshot
    }
}

public struct DiffEnvelope: Sendable, Codable {
    public let format: String
    public let schemaVersion: SchemaVersion
    public let exportedAt: Date
    public let diff: DiffResult

    public init(_ diff: DiffResult, exportedAt: Date? = nil) {
        format = "diffuse.diff"
        schemaVersion = .current
        self.exportedAt = exportedAt ?? diff.generatedAt
        self.diff = diff
    }
}
