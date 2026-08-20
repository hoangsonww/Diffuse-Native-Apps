import DiffuseModels
import Foundation

/// One step in the forward migration chain.
public protocol SnapshotMigration: Sendable {
    /// The version this migration reads.
    var from: SchemaVersion { get }

    /// The version this migration produces. Always `from + 1`.
    var to: SchemaVersion { get }

    func migrate(_ snapshot: Snapshot) throws -> Snapshot
}

/// Brings a snapshot written by an older build up to the current schema.
///
/// Migrations are strictly linear and forward-only. A user who has kept
/// snapshots for two years should be able to open all of them, and the cost of
/// that guarantee is one small migration per schema bump — paid once, on read.
public enum SnapshotMigrator {
    /// Registered migrations, ordered oldest first.
    ///
    /// Empty today because v1 is the first shipped format. The chain, the
    /// tests around it and the version stamped into every snapshot exist from
    /// day one so that adding v2 is a one-file change rather than an
    /// archaeology project.
    public static let migrations: [any SnapshotMigration] = []

    public static func migrate(_ snapshot: Snapshot, from version: SchemaVersion) throws -> Snapshot {
        guard version >= SchemaVersion.minimumSupported else {
            throw StorageError.unsupportedSchema(version)
        }
        guard version <= SchemaVersion.current else {
            // A snapshot from a newer build. Refusing is safer than silently
            // dropping fields we do not understand.
            throw StorageError.unsupportedSchema(version)
        }

        var current = snapshot
        var currentVersion = version

        while currentVersion < SchemaVersion.current {
            guard let migration = migrations.first(where: { $0.from == currentVersion }) else {
                throw StorageError.unsupportedSchema(currentVersion)
            }
            current = try migration.migrate(current)
            currentVersion = migration.to
        }

        return current
    }

    /// Whether a snapshot at this version can be read by this build.
    public static func canMigrate(from version: SchemaVersion) -> Bool {
        version >= SchemaVersion.minimumSupported && version <= SchemaVersion.current
    }

    /// Validates that the migration chain is complete and strictly increasing.
    /// Exercised by the test suite so a missing link is caught at build time
    /// rather than by a user with a two-year-old archive.
    public static func validateChain() -> [String] {
        var problems: [String] = []
        var expected = SchemaVersion.minimumSupported

        for migration in migrations {
            if migration.from != expected {
                problems.append("Expected a migration from \(expected), found one from \(migration.from).")
            }
            if migration.to.rawValue != migration.from.rawValue + 1 {
                problems.append("Migration \(migration.from) → \(migration.to) skips a version.")
            }
            expected = migration.to
        }

        if expected != SchemaVersion.current {
            problems.append("Migration chain ends at \(expected) but the current schema is \(SchemaVersion.current).")
        }

        return problems
    }
}
