#if os(macOS)

import DiffuseCapabilities
import DiffuseDeveloperTools
import DiffuseModels
import Foundation

public struct GitSnapshot: CollectedSection {
    public struct Repository: Sendable {
        public var path: String
        public var name: String
        public var branch: String?
        public var commit: String?
        public var modifiedFiles: Int
        public var untrackedFiles: Int
        public var ahead: Int
        public var behind: Int
        public var remoteHost: String?

        public init(
            path: String,
            name: String,
            branch: String?,
            commit: String?,
            modifiedFiles: Int,
            untrackedFiles: Int,
            ahead: Int,
            behind: Int,
            remoteHost: String?
        ) {
            self.path = path
            self.name = name
            self.branch = branch
            self.commit = commit
            self.modifiedFiles = modifiedFiles
            self.untrackedFiles = untrackedFiles
            self.ahead = ahead
            self.behind = behind
            self.remoteHost = remoteHost
        }
    }

    public let repositories: [Repository]
    public let diagnostics: [Diagnostic]

    public init(repositories: [Repository], diagnostics: [Diagnostic] = []) {
        self.repositories = repositories
        self.diagnostics = diagnostics
    }

    public static let schema = SectionSchema(
        capability: "development.git",
        displayName: "Git repositories",
        summary: "Branch, commit and working tree state for the repositories you watch.",
        category: .development,
        symbol: "arrow.triangle.branch",
        privacy: .sensitive,
        entityKinds: [
            EntityKindDescriptor(
                kind: .gitRepository,
                singularName: "Repository",
                pluralName: "Repositories",
                symbol: "arrow.triangle.branch",
                summary: "Metadata only. Diffuse records which branch and commit a repository is on, never "
                    + "the contents of any file.",
                additionSeverity: .notable,
                removalSeverity: .notable,
                properties: [
                    PropertyDescriptor(
                        key: .branch,
                        displayName: "Branch",
                        severity: .significant,
                        privacy: .sensitive,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .commit,
                        displayName: "Commit",
                        severity: .notable,
                        privacy: .sensitive,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .modifiedFileCount,
                        displayName: "Modified files",
                        unit: .count,
                        comparison: .exact,
                        severity: .informational,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .untrackedFileCount,
                        displayName: "Untracked files",
                        unit: .count,
                        comparison: .exact,
                        severity: .informational,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .aheadCount,
                        displayName: "Ahead",
                        unit: .count,
                        comparison: .exact,
                        severity: .notable,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .behindCount,
                        displayName: "Behind",
                        unit: .count,
                        comparison: .exact,
                        severity: .notable,
                        displayOrder: 5
                    ),
                    PropertyDescriptor(
                        key: "remoteHost",
                        displayName: "Remote host",
                        severity: .significant,
                        privacy: .sensitive,
                        displayOrder: 6
                    ),
                    PropertyDescriptor(
                        key: .repositoryPath,
                        displayName: "Path",
                        unit: .path,
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 7
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: "repositoryCount",
                displayName: "Repositories watched",
                unit: .count,
                comparison: .exact,
                severity: .notable
            ),
        ],
        displayOrder: 61
    )

    public var attributes: [PropertyKey: PropertyValue] {
        ["repositoryCount": .integer(Int64(repositories.count))]
    }

    public var status: CollectionStatus {
        repositories.isEmpty ? .unavailable : .collected
    }

    public var entities: [SnapshotEntity] {
        repositories.map { repository in
            SnapshotEntity(
                identity: .path(kind: .gitRepository, path: repository.path),
                displayName: repository.name,
                subtitle: repository.branch,
                properties: [
                    .branch: repository.branch.map { PropertyValue.string($0) } ?? .absent,
                    .commit: repository.commit.map { PropertyValue.identifier($0) } ?? .absent,
                    .modifiedFileCount: .integer(Int64(repository.modifiedFiles)),
                    .untrackedFileCount: .integer(Int64(repository.untrackedFiles)),
                    .aheadCount: .integer(Int64(repository.ahead)),
                    .behindCount: .integer(Int64(repository.behind)),
                    "remoteHost": repository.remoteHost.map { PropertyValue.string($0) } ?? .absent,
                    .repositoryPath: .path(repository.path),
                ],
                tags: repository.modifiedFiles > 0 ? ["dirty"] : ["clean"]
            )
        }
    }
}

/// Reads Git metadata for a set of watched repositories.
///
/// Strictly metadata. Diffuse runs `git status --porcelain` and reads the
/// counts, never the file names it prints, and never a file's contents. It
/// also never touches the network: no fetch, no remote query, and the
/// remote URL is reduced to its host so an internal hostname is all that
/// can appear in a diff.
public struct MacGitCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.development.git"
    public let version: SemanticVersion = "1.1.0"

    private let repositoryPaths: [String]
    private let runner: any ProcessRunning

    public init(repositoryPaths: [String], runner: any ProcessRunning = SystemProcessRunner()) {
        self.repositoryPaths = repositoryPaths
        self.runner = runner
    }

    public func collect(context: CollectionContext) async throws -> GitSnapshot {
        guard !repositoryPaths.isEmpty else {
            return GitSnapshot(
                repositories: [],
                diagnostics: [.info("No repositories are being watched. Add some in Settings.")]
            )
        }
        guard !context.isBackground else {
            return GitSnapshot(repositories: [], diagnostics: [.info("Skipped during a background capture")])
        }

        let paths = repositoryPaths
        let runner = runner

        // Repositories are read concurrently; a slow or broken one cannot
        // delay the others.
        let repositories = await withTaskGroup(of: GitSnapshot.Repository?.self) { group in
            for path in paths {
                group.addTask { await Self.read(path: path, runner: runner) }
            }
            var results: [GitSnapshot.Repository] = []
            for await repository in group {
                if let repository {
                    results.append(repository)
                }
            }
            return results.sorted { $0.path < $1.path }
        }

        let missing = paths.count - repositories.count
        return GitSnapshot(
            repositories: repositories,
            diagnostics: missing > 0
                ? [.warning("\(missing) watched path\(missing == 1 ? " is" : "s are") not a Git repository")]
                : []
        )
    }

    static func read(path: String, runner: any ProcessRunning) async -> GitSnapshot.Repository? {
        let expanded = (path as NSString).expandingTildeInPath
        guard
            let top = try? await runner.run(
                "git",
                ["-C", expanded, "rev-parse", "--show-toplevel"],
                timeout: .seconds(3)
            ),
            top.succeeded
        else { return nil }

        let root = top.output
        let name = (root as NSString).lastPathComponent

        async let branchResult = try? runner.run(
            "git",
            ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
            timeout: .seconds(3)
        )
        async let commitResult = try? runner.run(
            "git",
            ["-C", root, "rev-parse", "--short=8", "HEAD"],
            timeout: .seconds(3)
        )
        async let statusResult = try? runner.run(
            "git",
            ["-C", root, "status", "--porcelain=v1", "--untracked-files=normal"],
            timeout: .seconds(5)
        )
        async let trackingResult = try? runner.run(
            "git",
            ["-C", root, "rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            timeout: .seconds(3)
        )
        async let remoteResult = try? runner.run(
            "git",
            ["-C", root, "config", "--get", "remote.origin.url"],
            timeout: .seconds(3)
        )

        let status = await statusResult
        let counts = Self.countStatus(status?.output ?? "")
        let tracking = await Self.parseTracking(trackingResult)

        return await GitSnapshot.Repository(
            path: root,
            name: name,
            branch: branchResult.flatMap { $0.succeeded ? $0.output : nil },
            commit: commitResult.flatMap { $0.succeeded ? $0.output : nil },
            modifiedFiles: counts.modified,
            untrackedFiles: counts.untracked,
            ahead: tracking.ahead,
            behind: tracking.behind,
            remoteHost: remoteResult.flatMap { $0.succeeded ? Self.host(of: $0.output) : nil }
        )
    }

    /// Counts porcelain status lines by category. The file names on those
    /// lines are deliberately discarded.
    public static func countStatus(_ output: String) -> (modified: Int, untracked: Int) {
        var modified = 0
        var untracked = 0
        for line in output.split(separator: "\n") {
            guard line.count >= 2 else { continue }
            if line.hasPrefix("??") {
                untracked += 1
            } else {
                modified += 1
            }
        }
        return (modified, untracked)
    }

    /// Parses `rev-list --left-right --count @{upstream}...HEAD`, which
    /// prints `behind<TAB>ahead`.
    public static func parseTracking(_ result: ProcessResult?) -> (ahead: Int, behind: Int) {
        guard let result, result.succeeded else { return (0, 0) }
        let parts = result.output
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
            .compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (ahead: parts[1], behind: parts[0])
    }

    /// Reduces a remote URL to its host. `git@github.com:owner/repo.git`
    /// and `https://github.com/owner/repo` both become `github.com`, so a
    /// diff can show that a remote moved without publishing the repository
    /// path.
    public static func host(of url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = URL(string: trimmed), let host = parsed.host {
            return host
        }
        guard let atIndex = trimmed.firstIndex(of: "@") else { return nil }
        let remainder = trimmed[trimmed.index(after: atIndex)...]
        return remainder.split(whereSeparator: { $0 == ":" || $0 == "/" }).first.map(String.init)
    }
}

public extension MacGitCollector {
    static func capability(
        repositoryPaths: @escaping @Sendable () -> [String],
        runner: @escaping @Sendable () -> any ProcessRunning = { SystemProcessRunner() }
    ) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                GitSnapshot.self,
                summary: "Branch, commit and working tree state.",
                collectionDescription: "For each repository you choose to watch, records the current branch, "
                    + "the short commit hash, how many files are modified or untracked, how far ahead or "
                    + "behind the upstream you are, and the host of the origin remote. File names, file "
                    + "contents, commit messages and remote paths are never recorded, and no network "
                    + "request is made.",
                platforms: [.macOS],
                isEnabledByDefault: true,
                cost: .high,
                privacy: .sensitive
            ),
            availability: {
                guard await SystemProcessRunner().locate("git") != nil else {
                    return .unavailable(reason: "Git is not installed")
                }
                guard !repositoryPaths().isEmpty else {
                    return .unavailable(reason: "No repositories are being watched")
                }
                return .available
            },
            collector: { MacGitCollector(repositoryPaths: repositoryPaths(), runner: runner()) }
        ).erased
    }
}

#endif
