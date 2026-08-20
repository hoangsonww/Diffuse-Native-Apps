import DiffuseCapabilities
import DiffuseModels
import Foundation

/// The strongly typed result of reading basic operating system state.
///
/// A dedicated struct rather than a bag of key/value pairs: the collector body
/// stays readable and type-checked, and the projection into generic entities
/// happens in exactly one place.
public struct SystemInfoSnapshot: CollectedSection {
    public struct System: Sendable {
        public var osName: String
        public var osVersion: String
        public var kernelVersion: String
        public var hostName: String
        public var uptime: TimeInterval
        public var bootedAt: Date
        public var locale: String
        public var timeZone: String
        public var thermalState: String
        public var lowPowerMode: Bool
        public var processorCount: Int
        public var physicalMemory: Int64
    }

    public let system: System

    public init(system: System) {
        self.system = system
    }

    public static let schema = SectionSchema(
        capability: "system.info",
        displayName: "System",
        summary: "Operating system version, uptime, locale and thermal state.",
        category: .system,
        symbol: "cpu",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .system,
                singularName: "System",
                pluralName: "System",
                symbol: "cpu",
                additionSeverity: .informational,
                removalSeverity: .informational,
                properties: [
                    PropertyDescriptor(
                        key: .osName,
                        displayName: "Operating system",
                        severity: .critical,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .osVersion,
                        displayName: "Version",
                        summary: "An OS update is the single most common explanation for a behaviour change.",
                        unit: .version,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .kernelVersion,
                        displayName: "Kernel",
                        severity: .notable,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .hostName,
                        displayName: "Host name",
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .uptime,
                        displayName: "Uptime",
                        unit: .seconds,
                        // Uptime always changes; the interesting event is the
                        // reboot, which `bootedAt` captures precisely.
                        comparison: .ignored,
                        severity: .informational,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .bootedAt,
                        displayName: "Last booted",
                        summary: "A change here means the device restarted between snapshots.",
                        unit: .timestamp,
                        comparison: .numeric(tolerance: 120),
                        severity: .significant,
                        displayOrder: 5
                    ),
                    PropertyDescriptor(key: .locale, displayName: "Locale", severity: .notable, displayOrder: 6),
                    PropertyDescriptor(key: .timeZone, displayName: "Time zone", severity: .notable, displayOrder: 7),
                    PropertyDescriptor(
                        key: .thermalState,
                        displayName: "Thermal state",
                        severity: .notable,
                        displayOrder: 8
                    ),
                    PropertyDescriptor(
                        key: .lowPowerMode,
                        displayName: "Low Power Mode",
                        severity: .notable,
                        displayOrder: 9
                    ),
                    PropertyDescriptor(
                        key: .physicalMemory,
                        displayName: "Physical memory",
                        unit: .bytes,
                        comparison: .exact,
                        severity: .significant,
                        displayOrder: 10
                    ),
                    PropertyDescriptor(
                        key: .coreCount,
                        displayName: "Logical cores",
                        unit: .count,
                        severity: .significant,
                        displayOrder: 11
                    ),
                ]
            ),
        ],
        displayOrder: 0
    )

    public var entities: [SnapshotEntity] {
        [
            SnapshotEntity(
                kind: .system,
                id: "primary",
                displayName: system.osName,
                subtitle: system.osVersion,
                properties: [
                    .osName: .string(system.osName),
                    .osVersion: .version(SemanticVersion(system.osVersion) ?? SemanticVersion(0)),
                    .kernelVersion: .string(system.kernelVersion),
                    .hostName: .string(system.hostName),
                    .uptime: .duration(system.uptime),
                    .bootedAt: .timestamp(system.bootedAt),
                    .locale: .string(system.locale),
                    .timeZone: .string(system.timeZone),
                    .thermalState: .string(system.thermalState),
                    .lowPowerMode: .boolean(system.lowPowerMode),
                    .physicalMemory: .bytes(system.physicalMemory),
                    .coreCount: .integer(Int64(system.processorCount)),
                ]
            ),
        ]
    }
}

/// Reads operating system state from `ProcessInfo`.
///
/// Available on every Apple platform, which makes it the one capability that
/// appears in all four apps and gives cross-platform snapshots a common spine.
public struct SystemInfoCollector: SnapshotCollector {
    public let identifier: CollectorID = "shared.system.info"
    public let version: SemanticVersion = "1.0.0"

    private let osNameOverride: String?

    public init(osName: String? = nil) {
        osNameOverride = osName
    }

    public func collect(context: CollectionContext) async throws -> SystemInfoSnapshot {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion

        return SystemInfoSnapshot(
            system: .init(
                osName: osNameOverride ?? context.platform.rawValue,
                osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                kernelVersion: Self.sysctlString("kern.osversion") ?? "unknown",
                hostName: info.hostName,
                uptime: info.systemUptime,
                // Rounded to the minute so clock jitter between two readings
                // does not read as a reboot.
                bootedAt: Self.roundToMinute(context.startedAt.addingTimeInterval(-info.systemUptime)),
                locale: Locale.current.identifier,
                timeZone: TimeZone.current.identifier,
                thermalState: Self.describe(info.thermalState),
                lowPowerMode: info.isLowPowerModeEnabled,
                processorCount: info.processorCount,
                physicalMemory: Int64(info.physicalMemory)
            )
        )
    }

    static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    static func roundToMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            var small: Int32 = 0
            var smallSize = MemoryLayout<Int32>.size
            guard sysctlbyname(name, &small, &smallSize, nil, 0) == 0 else { return nil }
            return Int64(small)
        }
        return value
    }
}

public extension SystemInfoCollector {
    /// The capability wrapper, ready to register.
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                SystemInfoSnapshot.self,
                summary: "Which OS you are on and how long it has been running.",
                collectionDescription: "Reads the operating system name and version, kernel build, host name, "
                    + "uptime, locale, time zone, thermal state, Low Power Mode, memory size and core count. "
                    + "All of this comes from ProcessInfo and requires no permission.",
                platforms: platforms,
                cost: .low
            ),
            collector: { SystemInfoCollector() }
        ).erased
    }
}
