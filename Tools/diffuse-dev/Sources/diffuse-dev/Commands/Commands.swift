import DiffuseCapabilities
import DiffuseCollectors
import DiffuseCore
import DiffuseDeveloperTools
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import Foundation

// MARK: - Shared plumbing

enum Runtime {
    /// The registry for the platform the CLI is running on.
    ///
    /// The tool is built for macOS in practice, but the code path is written so
    /// that a future Linux or tvOS host would only need its own registry.
    static func makeCatalog(repositories: [String]) -> CapabilityCatalog {
        #if os(macOS)
        let registry = MacCapabilityRegistry(watchedRepositoryPaths: { repositories })
        #else
        let registry = StaticCapabilityRegistry(
            platform: Platform.current,
            capabilities: [
                SystemInfoCollector.capability(platforms: [Platform.current]),
                StorageCollector.capability(platforms: [Platform.current], enumeratesAllVolumes: false),
                NetworkInterfaceCollector.capability(platforms: [Platform.current]),
                NetworkPathCollector.capability(platforms: [Platform.current]),
            ]
        )
        #endif
        return CapabilityCatalog(registry: registry)
    }

    static func makeCoordinator(catalog: CapabilityCatalog, now: Date? = nil) -> SnapshotCoordinator {
        SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: "diffuse-dev"),
            platform: Platform.current,
            timeSource: now.map { FixedTimeSource($0) } ?? SystemTimeSource(),
            appVersion: "1.0.0"
        )
    }

    static func repositories(from arguments: Arguments) -> [String] {
        arguments.value("repos")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            ?? []
    }

    static func severity(from arguments: Arguments) throws -> ChangeSeverity {
        guard let raw = arguments.value("severity") else { return .informational }
        guard let severity = ChangeSeverity(rawValue: raw) else {
            throw CLIError.usage("Unknown severity '\(raw)'. Expected one of: "
                + ChangeSeverity.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return severity
    }

    static func loadSnapshot(at path: String) throws -> Snapshot {
        let url = URL.resolving(path: path)
        guard let data = try? Data(contentsOf: url) else {
            throw CLIError.failure("Could not read \(url.path)")
        }
        do {
            return try SnapshotCoding.decodeSnapshot(data)
        } catch {
            throw CLIError.failure("\(url.lastPathComponent) is not a valid snapshot: \(error)")
        }
    }

    static func write(_ data: Data, to path: String?) throws -> String? {
        guard let path else { return nil }
        let url = URL.resolving(path: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CLIError.failure("Could not write \(url.path): \(error.localizedDescription)")
        }
        return url.path
    }
}

// MARK: - capabilities

enum CapabilitiesCommand {
    static func run(_ arguments: Arguments) async throws {
        let catalog = Runtime.makeCatalog(repositories: Runtime.repositories(from: arguments))
        let statuses = await catalog.refresh()

        if arguments.has("json") {
            let payload = statuses.map { status in
                CapabilityReport(
                    id: status.metadata.id,
                    displayName: status.metadata.displayName,
                    category: status.metadata.category,
                    available: status.availability.isAvailable,
                    state: status.availability.displayName,
                    detail: status.availability.detail,
                    privacy: status.metadata.privacy,
                    cost: status.metadata.cost
                )
            }
            let data = try SnapshotCoding.makeEncoder().encode(payload)
            Terminal.print(String(decoding: data, as: UTF8.self))
            return
        }

        let available = statuses.filter(\.availability.isAvailable)
        let unavailable = statuses.filter { !$0.availability.isAvailable && $0.availability.isDiscoverable }

        Terminal.heading("Capabilities on \(Platform.current.rawValue)")
        Terminal.print()

        if !available.isEmpty {
            Terminal.print(Terminal.styled("Available:", .bold))
            for status in available.sorted(by: { $0.metadata.id < $1.metadata.id }) {
                Terminal.print("  " + Terminal.styled("✓", .green) + " " + pad(status.metadata.id.rawValue)
                    + Terminal.styled(status.metadata.displayName, .dim))
            }
            Terminal.print()
        }

        if !unavailable.isEmpty {
            Terminal.print(Terminal.styled("Unavailable:", .bold))
            for status in unavailable.sorted(by: { $0.metadata.id < $1.metadata.id }) {
                let marker = status.availability.isRetryable ? Terminal.styled("○", .dim) : Terminal.styled(
                    "⚠",
                    .yellow
                )
                let reason = status.availability.detail.map { " — \($0)" } ?? ""
                Terminal.print("  " + marker + " " + pad(status.metadata.id.rawValue)
                    + Terminal.styled(status.availability.displayName + reason, .dim))
            }
            Terminal.print()
        }

        Terminal.print(Terminal.styled(
            "\(available.count) of \(statuses.count) capabilities will contribute to the next snapshot.",
            .dim
        ))
    }

    private static func pad(_ text: String) -> String {
        text.padding(toLength: 28, withPad: " ", startingAt: 0)
    }

    private struct CapabilityReport: Codable {
        let id: CapabilityID
        let displayName: String
        let category: SectionCategory
        let available: Bool
        let state: String
        let detail: String?
        let privacy: PrivacyClassification
        let cost: CollectionCost
    }
}

// MARK: - snapshot

enum SnapshotCommand {
    static func run(_ arguments: Arguments) async throws {
        let catalog = Runtime.makeCatalog(repositories: Runtime.repositories(from: arguments))
        let coordinator = Runtime.makeCoordinator(catalog: catalog)

        let report = await coordinator.capture(
            origin: .manual,
            label: arguments.value("label"),
            tags: ["cli"]
        )

        let data = try SnapshotCoding.encode(report.snapshot, prettyPrinted: !arguments.has("compact"))

        if let path = try Runtime.write(data, to: arguments.positional(0)) {
            Terminal.print(Terminal.styled("✓", .green) + " Wrote \(path)")
        } else if arguments.has("json") {
            Terminal.print(String(decoding: data, as: UTF8.self))
            return
        }

        Terminal.print()
        Terminal.heading("Snapshot \(report.snapshot.id.shortValue)")
        Terminal.print()
        Terminal.print("  Captured    \(report.snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
        Terminal.print("  Platform    \(report.snapshot.platform.rawValue) · \(report.snapshot.device.model)")
        Terminal.print("  Sections    \(report.snapshot.sections.count)")
        Terminal.print("  Entities    \(report.snapshot.entityCount)")
        Terminal.print("  Duration    \(String(format: "%.2f", report.totalDuration))s")
        Terminal.print()

        for outcome in report.outcomes.sorted(by: { $0.duration > $1.duration }) {
            let marker: String = switch outcome.result {
            case .collected: Terminal.styled("✓", .green)
            case .placeholder, .skipped: Terminal.styled("○", .dim)
            case .failed: Terminal.styled("✗", .red)
            }
            let detail: String = switch outcome.result {
            case let .collected(count): "\(count) entities"
            case let .placeholder(status): status.displayName
            case .skipped: "disabled"
            case let .failed(error): error.message
            }
            Terminal.print("  \(marker) "
                + outcome.capability.rawValue.padding(toLength: 28, withPad: " ", startingAt: 0)
                + Terminal.styled(detail.padding(toLength: 24, withPad: " ", startingAt: 0), .dim)
                + Terminal.styled(String(format: "%6.0fms", outcome.duration * 1000), .dim))
        }
    }
}

// MARK: - inspect

enum InspectCommand {
    static func run(_ arguments: Arguments) async throws {
        guard let path = arguments.positional(0) else {
            throw CLIError.usage("Usage: diffuse-dev inspect <snapshot.json>")
        }
        let snapshot = try Runtime.loadSnapshot(at: path)

        if arguments.has("markdown") {
            Terminal.print(ReportRenderer.markdown(for: snapshot))
            return
        }

        Terminal.heading("Snapshot \(snapshot.id.shortValue)")
        Terminal.print()
        Terminal.print("  Captured    \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
        Terminal.print("  Origin      \(snapshot.origin.displayName)")
        Terminal.print("  Platform    \(snapshot.platform.rawValue) \(snapshot.device.systemVersion)")
        Terminal.print("  Device      \(snapshot.device.name) · \(snapshot.device.model)")
        Terminal.print("  Schema      v\(snapshot.schemaVersion)")
        Terminal.print("  Sections    \(snapshot.sections.count)")
        Terminal.print("  Entities    \(snapshot.entityCount)")
        if let label = snapshot.label {
            Terminal.print("  Label       \(label)")
        }
        Terminal.print()

        for section in snapshot.orderedSections {
            let marker = section.status.hasData ? Terminal.styled("✓", .green) : Terminal.styled("○", .yellow)
            Terminal.print("  \(marker) "
                + section.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
                + Terminal.styled(
                    "\(section.entityCount) entities".padding(toLength: 16, withPad: " ", startingAt: 0),
                    .dim
                )
                + Terminal.styled(section.status.displayName, .dim))

            if arguments.has("verbose") {
                for entity in section.sortedEntities {
                    Terminal.print("      " + Terminal.styled("· ", .dim) + entity.displayName)
                    for key in entity.sortedPropertyKeys {
                        let descriptor = section.schema.descriptor(for: key, in: entity.kind)
                        Terminal.print("        "
                            + Terminal.styled(
                                descriptor.displayName.padding(toLength: 22, withPad: " ", startingAt: 0),
                                .dim
                            )
                            + entity[key].formatted())
                    }
                }
                for diagnostic in section.diagnostics {
                    Terminal.print("      " + Terminal.styled("! \(diagnostic.message)", .yellow))
                }
            }
        }
    }
}

// MARK: - diff

enum DiffCommand {
    static func run(_ arguments: Arguments) async throws {
        guard let basePath = arguments.positional(0), let targetPath = arguments.positional(1) else {
            throw CLIError.usage("Usage: diffuse-dev diff <before.json> <after.json>")
        }

        let base = try Runtime.loadSnapshot(at: basePath)
        let target = try Runtime.loadSnapshot(at: targetPath)
        let severity = try Runtime.severity(from: arguments)

        let engine = DiffEngine(
            options: DiffOptions(
                minimumSeverity: .informational,
                includeUnchanged: arguments.has("verbose")
            )
        )
        let result = engine.diff(base: base, target: target)

        if arguments.has("json") {
            let data = try SnapshotCoding.encode(result, prettyPrinted: !arguments.has("compact"))
            Terminal.print(String(decoding: data, as: UTF8.self))
            return
        }
        if arguments.has("markdown") {
            Terminal.print(ReportRenderer.markdown(for: result, minimumSeverity: severity))
            return
        }

        Terminal.print(ReportRenderer.plainText(for: result, minimumSeverity: severity))

        // A non-zero exit when significant changes exist makes the CLI usable
        // as a CI gate: "fail the job if the build environment drifted".
        if arguments.has("fail-on-change"), result.summary.significantCount > 0 {
            exit(2)
        }
    }
}

// MARK: - validate

enum ValidateCommand {
    static func run(_ arguments: Arguments) async throws {
        guard let path = arguments.positional(0) else {
            throw CLIError.usage("Usage: diffuse-dev validate <snapshot.json>")
        }

        let snapshot = try Runtime.loadSnapshot(at: path)
        let problems = SnapshotValidator.validate(snapshot)

        Terminal.heading("Validating \(URL.resolving(path: path).lastPathComponent)")
        Terminal.print()

        guard !problems.isEmpty else {
            Terminal.print("  " + Terminal.styled("✓", .green) + " Valid against schema v\(SchemaVersion.current)")
            Terminal
                .print("  " + Terminal
                    .styled("✓", .green) + " \(snapshot.sections.count) sections, \(snapshot.entityCount) entities")
            Terminal.print("  " + Terminal.styled("✓", .green) + " Round-trips through JSON without loss")
            return
        }

        for problem in problems {
            Terminal.print("  " + Terminal.styled("✗", .red) + " " + problem)
        }
        exit(1)
    }
}

// MARK: - privacy

enum PrivacyCommand {
    static func run(_ arguments: Arguments) async throws {
        let catalog = Runtime.makeCatalog(repositories: Runtime.repositories(from: arguments))
        await catalog.refresh()
        let ledger = await PrivacyLedger(statuses: catalog.statuses())
        Terminal.print(ledger.markdown())
    }
}

// MARK: - generate-fixture

enum GenerateFixtureCommand {
    static func run(_ arguments: Arguments) async throws {
        let directory = arguments.value("output").map(URL.resolving(path:))
            ?? URL.resolving(path: "Fixtures")
        let written = try FixtureGenerator.writeAll(to: directory)

        Terminal.heading("Fixtures")
        Terminal.print()
        for path in written {
            Terminal.print("  " + Terminal.styled("✓", .green) + " " + path)
        }
        Terminal.print()
        Terminal.print(Terminal.styled("\(written.count) files written to \(directory.path)", .dim))
    }
}
