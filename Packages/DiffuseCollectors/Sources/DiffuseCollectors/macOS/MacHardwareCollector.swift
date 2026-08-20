#if os(macOS)

import DiffuseCapabilities
import DiffuseModels
import Foundation

public struct MacHardwareSnapshot: CollectedSection {
    public struct Machine: Sendable {
        public var modelIdentifier: String
        public var marketingName: String?
        public var processor: String
        public var totalCores: Int
        public var performanceCores: Int
        public var efficiencyCores: Int
        public var memory: Int64
        public var architecture: String
    }

    public let machine: Machine

    public init(machine: Machine) {
        self.machine = machine
    }

    public static let schema = SectionSchema(
        capability: "hardware.machine",
        displayName: "Hardware",
        summary: "The machine itself: chip, cores and installed memory.",
        category: .hardware,
        symbol: "desktopcomputer",
        privacy: .public,
        entityKinds: [
            EntityKindDescriptor(
                kind: .machine,
                singularName: "Machine",
                pluralName: "Machine",
                symbol: "desktopcomputer",
                // Hardware should not change between snapshots. If it does,
                // the library is being shared across machines, and that is
                // worth flagging loudly.
                additionSeverity: .critical,
                removalSeverity: .critical,
                properties: [
                    PropertyDescriptor(
                        key: .modelIdentifier,
                        displayName: "Model identifier",
                        severity: .critical,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .processor,
                        displayName: "Chip",
                        severity: .critical,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .coreCount,
                        displayName: "Total cores",
                        unit: .count,
                        severity: .critical,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .performanceCoreCount,
                        displayName: "Performance cores",
                        unit: .count,
                        severity: .significant,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .efficiencyCoreCount,
                        displayName: "Efficiency cores",
                        unit: .count,
                        severity: .significant,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .physicalMemory,
                        displayName: "Memory",
                        unit: .bytes,
                        comparison: .exact,
                        severity: .critical,
                        displayOrder: 5
                    ),
                    PropertyDescriptor(
                        key: .architecture,
                        displayName: "Architecture",
                        severity: .critical,
                        displayOrder: 6
                    ),
                ]
            ),
        ],
        displayOrder: 10
    )

    public var entities: [SnapshotEntity] {
        [
            SnapshotEntity(
                kind: .machine,
                id: machine.modelIdentifier,
                displayName: machine.marketingName ?? machine.modelIdentifier,
                subtitle: machine.processor,
                properties: [
                    .modelIdentifier: .identifier(machine.modelIdentifier),
                    .processor: .string(machine.processor),
                    .coreCount: .integer(Int64(machine.totalCores)),
                    .performanceCoreCount: .integer(Int64(machine.performanceCores)),
                    .efficiencyCoreCount: .integer(Int64(machine.efficiencyCores)),
                    .physicalMemory: .bytes(machine.memory),
                    .architecture: .string(machine.architecture),
                ]
            ),
        ]
    }
}

/// Reads machine hardware from `sysctl`.
public struct MacHardwareCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.hardware.machine"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    public func collect(context _: CollectionContext) async throws -> MacHardwareSnapshot {
        let model = SystemInfoCollector.sysctlString("hw.model") ?? "unknown"
        let brand = SystemInfoCollector.sysctlString("machdep.cpu.brand_string") ?? "Unknown processor"

        return MacHardwareSnapshot(
            machine: .init(
                modelIdentifier: model,
                marketingName: nil,
                processor: brand,
                totalCores: Int(SystemInfoCollector.sysctlInt("hw.ncpu") ?? 0),
                performanceCores: Int(SystemInfoCollector.sysctlInt("hw.perflevel0.logicalcpu") ?? 0),
                efficiencyCores: Int(SystemInfoCollector.sysctlInt("hw.perflevel1.logicalcpu") ?? 0),
                memory: SystemInfoCollector.sysctlInt("hw.memsize") ?? 0,
                architecture: ProcessInfoDeviceIdentityProviderArchitecture.current
            )
        )
    }
}

/// Small indirection so the collector does not import `DiffuseCore` purely
/// to read the architecture string.
enum ProcessInfoDeviceIdentityProviderArchitecture {
    static var current: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

public extension MacHardwareCollector {
    static var capability: AnyCapability {
        BasicCapability(
            metadata: .describing(
                MacHardwareSnapshot.self,
                summary: "Chip, core layout and installed memory.",
                collectionDescription: "Reads the machine model identifier, CPU brand string, core counts, "
                    + "memory size and architecture from sysctl. No serial number is read.",
                platforms: [.macOS],
                cost: .low
            ),
            collector: { MacHardwareCollector() }
        ).erased
    }
}

#endif
