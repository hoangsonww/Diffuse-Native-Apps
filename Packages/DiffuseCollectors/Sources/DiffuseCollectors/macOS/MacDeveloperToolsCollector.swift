#if os(macOS)

import DiffuseCapabilities
import DiffuseDeveloperTools
import DiffuseModels
import Foundation

public struct DeveloperToolsSnapshot: CollectedSection {
    public let observations: [ToolObservation]
    public let diagnostics: [Diagnostic]

    public init(observations: [ToolObservation], diagnostics: [Diagnostic] = []) {
        self.observations = observations
        self.diagnostics = diagnostics
    }

    public static let schema = SectionSchema(
        capability: "development.tools",
        displayName: "Developer tools",
        summary: "Command line toolchains installed on this Mac, and their versions.",
        category: .development,
        symbol: "hammer",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .developerTool,
                singularName: "Tool",
                pluralName: "Tools",
                symbol: "terminal",
                summary: "A command line tool discovered on PATH. Only tools that are actually installed "
                    + "appear — there is no list of tools you do not have.",
                additionSeverity: .significant,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .version,
                        displayName: "Version",
                        summary: "Compared by semantic version precedence, so a major bump or a downgrade "
                            + "is escalated above a patch release.",
                        unit: .version,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: "rawVersion",
                        displayName: "Reported version",
                        severity: .notable,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .executablePath,
                        displayName: "Path",
                        summary: "A tool moving between /opt/homebrew and /usr/local usually means the "
                            + "install source changed.",
                        unit: .path,
                        severity: .significant,
                        privacy: .sensitive,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: "execPath",
                        displayName: "Runtime path",
                        unit: .path,
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: "prefix",
                        displayName: "Prefix",
                        unit: .path,
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 4
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: "toolCount",
                displayName: "Tools detected",
                unit: .count,
                comparison: .exact,
                severity: .notable
            ),
        ],
        displayOrder: 60
    )

    public var attributes: [PropertyKey: PropertyValue] {
        ["toolCount": .integer(Int64(observations.count))]
    }

    public var status: CollectionStatus {
        observations.isEmpty ? .unavailable : .collected
    }

    public var entities: [SnapshotEntity] {
        observations.map { observation in
            var properties: [PropertyKey: PropertyValue] = [
                .version: observation.version.map { PropertyValue.version($0) }
                    ?? .string(observation.rawVersion),
                "rawVersion": .string(observation.rawVersion),
                .executablePath: .path(observation.executablePath),
            ]
            for (key, value) in observation.details {
                properties[key] = value
            }

            return SnapshotEntity(
                kind: .developerTool,
                id: observation.adapter,
                displayName: observation.displayName,
                subtitle: observation.rawVersion,
                properties: properties,
                tags: ["tool"]
            )
        }
    }
}

/// Probes the developer toolchains installed on this Mac.
///
/// This is the capability-driven design at its most visible: the collector
/// contains no mention of Node, Docker or Rust. It runs whatever adapters
/// it is given, and each tool that is not installed simply produces no
/// entity — which is why the UI never shows "Rust: not supported".
public struct MacDeveloperToolsCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.development.tools"
    public let version: SemanticVersion = "1.1.0"

    private let adapters: [ToolAdapter]
    private let runner: any ProcessRunning

    public init(
        adapters: [ToolAdapter] = BuiltInToolAdapters.all,
        runner: any ProcessRunning = SystemProcessRunner()
    ) {
        self.adapters = adapters
        self.runner = runner
    }

    public func collect(context: CollectionContext) async throws -> DeveloperToolsSnapshot {
        // Background captures on macOS still run, but probing a dozen
        // subprocesses is not something to do opportunistically.
        guard !context.isBackground else {
            return DeveloperToolsSnapshot(
                observations: [],
                diagnostics: [.info("Skipped during a background capture")]
            )
        }

        let observations = await ToolProbe(runner: runner).probe(adapters)
        return DeveloperToolsSnapshot(
            observations: observations,
            diagnostics: observations.isEmpty
                ? [.info("No supported developer tools found on PATH")]
                : []
        )
    }
}

public extension MacDeveloperToolsCollector {
    static func capability(
        adapters: [ToolAdapter] = BuiltInToolAdapters.all,
        runner: @escaping @Sendable () -> any ProcessRunning = { SystemProcessRunner() }
    ) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                DeveloperToolsSnapshot.self,
                summary: "Which toolchains are installed, and at what versions.",
                collectionDescription: "Runs each known tool's version command (for example `node --version`) "
                    + "and records the version and the path it was found at. No source code, project files "
                    + "or environment variable values are read.",
                platforms: [.macOS],
                cost: .high
            ),
            collector: { MacDeveloperToolsCollector(adapters: adapters, runner: runner()) }
        ).erased
    }
}

#endif
