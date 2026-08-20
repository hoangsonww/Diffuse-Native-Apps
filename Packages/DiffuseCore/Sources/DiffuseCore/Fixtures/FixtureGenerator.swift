import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import Foundation

/// Writes the golden fixtures the regression suite compares against.
///
/// The fixtures are checked in. When a change to the diff engine alters the
/// output, the test suite fails with a readable JSON diff, and regenerating is
/// a deliberate act with a reviewable result — which is the entire point.
public enum FixtureGenerator {
    public struct SnapshotFixture: Sendable {
        public let name: String
        public let snapshot: Snapshot
    }

    public struct DiffFixture: Sendable {
        public let name: String
        public let base: Snapshot
        public let target: Snapshot
        public let options: DiffOptions
    }

    public static let snapshots: [SnapshotFixture] = [
        SnapshotFixture(name: "mac-baseline", snapshot: SampleData.macBaseline),
        SnapshotFixture(name: "mac-after-workday", snapshot: SampleData.macAfterWorkday),
        SnapshotFixture(name: "mac-permission-problem", snapshot: SampleData.macWithPermissionProblem),
        SnapshotFixture(name: "ios-baseline", snapshot: SampleData.iosBaseline),
        SnapshotFixture(name: "ios-afternoon", snapshot: SampleData.iosAfternoon),
    ]

    public static let diffs: [DiffFixture] = [
        DiffFixture(
            name: "mac-workday",
            base: SampleData.macBaseline,
            target: SampleData.macAfterWorkday,
            options: .default
        ),
        DiffFixture(
            name: "mac-workday-significant",
            base: SampleData.macBaseline,
            target: SampleData.macAfterWorkday,
            options: .significantOnly
        ),
        DiffFixture(
            name: "mac-permission-loss",
            base: SampleData.macAfterWorkday,
            target: SampleData.macWithPermissionProblem,
            options: .default
        ),
        DiffFixture(
            name: "ios-day",
            base: SampleData.iosBaseline,
            target: SampleData.iosAfternoon,
            options: .default
        ),
    ]

    /// Regenerates every fixture, returning the relative paths written.
    @discardableResult
    public static func writeAll(to directory: URL) throws -> [String] {
        let snapshotsDirectory = directory.appendingPathComponent("snapshots", isDirectory: true)
        let diffsDirectory = directory.appendingPathComponent("diffs", isDirectory: true)

        for url in [snapshotsDirectory, diffsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        var written: [String] = []

        for fixture in snapshots {
            let url = snapshotsDirectory.appendingPathComponent("\(fixture.name).json")
            try SnapshotCoding.encode(fixture.snapshot).write(to: url, options: .atomic)
            written.append("snapshots/\(fixture.name).json")
        }

        for fixture in diffs {
            let result = DiffEngine(options: fixture.options).diff(base: fixture.base, target: fixture.target)
            let url = diffsDirectory.appendingPathComponent("\(fixture.name).expected.json")
            try SnapshotCoding.encode(result).write(to: url, options: .atomic)
            written.append("diffs/\(fixture.name).expected.json")
        }

        return written.sorted()
    }

    /// The expected diff for a named fixture, computed rather than read. Tests
    /// compare this against the checked-in file.
    public static func expectedDiff(named name: String) -> DiffResult? {
        guard let fixture = diffs.first(where: { $0.name == name }) else { return nil }
        return DiffEngine(options: fixture.options).diff(base: fixture.base, target: fixture.target)
    }

    public static func snapshot(named name: String) -> Snapshot? {
        snapshots.first { $0.name == name }?.snapshot
    }
}
