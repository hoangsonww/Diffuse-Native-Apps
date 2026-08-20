#if os(macOS)

import DiffuseCapabilities
import DiffuseDeveloperTools
import DiffuseModels
import Foundation

public struct ProcessSnapshot: CollectedSection {
    public struct RunningProcess: Sendable {
        public var name: String
        public var residentMemory: Int64
        public var cpuPercent: Double

        public init(name: String, residentMemory: Int64, cpuPercent: Double) {
            self.name = name
            self.residentMemory = residentMemory
            self.cpuPercent = cpuPercent
        }
    }

    public let processes: [RunningProcess]
    public let totalCount: Int

    public init(processes: [RunningProcess], totalCount: Int) {
        self.processes = processes
        self.totalCount = totalCount
    }

    public static let schema = SectionSchema(
        capability: "system.processes",
        displayName: "Processes",
        summary: "The heaviest processes running, by memory.",
        category: .system,
        symbol: "list.bullet.rectangle",
        privacy: .sensitive,
        entityKinds: [
            EntityKindDescriptor(
                kind: .process,
                singularName: "Process",
                pluralName: "Processes",
                symbol: "gearshape",
                summary: "Identified by executable name, aggregated across instances. Command line "
                    + "arguments are never recorded, because they routinely contain tokens and paths.",
                additionSeverity: .notable,
                removalSeverity: .notable,
                properties: [
                    PropertyDescriptor(
                        key: .memoryFootprint,
                        displayName: "Memory",
                        unit: .bytes,
                        comparison: .relative(tolerance: 0.25),
                        severity: .informational,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .cpuUsage,
                        displayName: "CPU",
                        unit: .percent,
                        comparison: .numeric(tolerance: 0.10),
                        severity: .informational,
                        displayOrder: 1
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: .processCount,
                displayName: "Processes running",
                summary: "Process counts fluctuate constantly, so a swing of fewer than ten is ignored.",
                unit: .count,
                comparison: .numeric(tolerance: 10),
                severity: .informational
            ),
        ],
        displayOrder: 5
    )

    public var attributes: [PropertyKey: PropertyValue] {
        [.processCount: .integer(Int64(totalCount))]
    }

    public var entities: [SnapshotEntity] {
        processes.map { process in
            SnapshotEntity(
                kind: .process,
                id: process.name,
                displayName: process.name,
                properties: [
                    .memoryFootprint: .bytes(process.residentMemory),
                    .cpuUsage: .percentage(process.cpuPercent / 100),
                ]
            )
        }
    }
}

/// Lists the heaviest running processes via `ps`.
///
/// Only executable names, resident memory and CPU share are kept. Arguments
/// are discarded before they reach a snapshot: `--token=…` in a command
/// line is exactly the kind of thing Diffuse promises never to store.
public struct MacProcessCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.system.processes"
    public let version: SemanticVersion = "1.0.0"

    private let runner: any ProcessRunning
    private let limit: Int

    public init(runner: any ProcessRunning = SystemProcessRunner(), limit: Int = 12) {
        self.runner = runner
        self.limit = limit
    }

    public func collect(context _: CollectionContext) async throws -> ProcessSnapshot {
        let result = try await runner.run("ps", ["-axco", "rss=,pcpu=,comm="], timeout: .seconds(5))
        guard result.succeeded else {
            throw CollectorError.malformedOutput("ps exited with code \(result.exitCode)")
        }

        var aggregated: [String: ProcessSnapshot.RunningProcess] = [:]
        var total = 0

        for line in result.lines {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let rss = Int64(fields[0]), let cpu = Double(fields[1]) else { continue }
            total += 1

            let name = fields[2...].joined(separator: " ")
            // `ps` reports kilobytes.
            let bytes = rss * 1024
            if var existing = aggregated[name] {
                existing.residentMemory += bytes
                existing.cpuPercent += cpu
                aggregated[name] = existing
            } else {
                aggregated[name] = ProcessSnapshot.RunningProcess(
                    name: name,
                    residentMemory: bytes,
                    cpuPercent: cpu
                )
            }
        }

        let heaviest = aggregated.values
            .sorted {
                if $0.residentMemory != $1.residentMemory {
                    return $0.residentMemory > $1.residentMemory
                }
                return $0.name < $1.name
            }
            .prefix(limit)

        return ProcessSnapshot(
            processes: Array(heaviest).sorted { $0.name < $1.name },
            totalCount: total
        )
    }
}

public extension MacProcessCollector {
    static func capability(
        runner: @escaping @Sendable () -> any ProcessRunning = { SystemProcessRunner() }
    ) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                ProcessSnapshot.self,
                summary: "The heaviest processes and how many are running.",
                collectionDescription: "Runs `ps` and keeps only executable names, resident memory and CPU "
                    + "share for the heaviest processes. Command line arguments, which frequently contain "
                    + "tokens and file paths, are discarded and never stored.",
                platforms: [.macOS],
                isEnabledByDefault: false,
                cost: .moderate,
                privacy: .sensitive
            ),
            collector: { MacProcessCollector(runner: runner()) }
        ).erased
    }
}

#endif
