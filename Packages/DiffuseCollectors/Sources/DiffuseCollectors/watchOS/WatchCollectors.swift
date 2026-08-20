#if os(watchOS)

import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import Foundation
import WatchKit

public struct WatchDeviceSnapshot: CollectedSection {
    public struct Device: Sendable {
        public var name: String
        public var model: String
        public var systemVersion: String
        public var screenWidth: Int
        public var screenHeight: Int
        public var waterResistanceDepth: Int
    }

    public let device: Device

    public init(device: Device) {
        self.device = device
    }

    public static let schema = SectionSchema(
        capability: "device.info",
        displayName: "Device",
        summary: "Watch model and system version.",
        category: .hardware,
        symbol: "applewatch",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .machine,
                singularName: "Watch",
                pluralName: "Watch",
                symbol: "applewatch",
                additionSeverity: .critical,
                removalSeverity: .critical,
                properties: [
                    PropertyDescriptor(
                        key: .model,
                        displayName: "Model",
                        severity: .critical,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .osVersion,
                        displayName: "System version",
                        unit: .version,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .resolution,
                        displayName: "Screen",
                        unit: .pixels,
                        severity: .significant,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .hostName,
                        displayName: "Name",
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 3
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
                id: device.model,
                displayName: device.model,
                subtitle: "watchOS \(device.systemVersion)",
                properties: [
                    .model: .string(device.model),
                    .osVersion: SemanticVersion(device.systemVersion).map { PropertyValue.version($0) }
                        ?? .string(device.systemVersion),
                    .resolution: .string("\(device.screenWidth) × \(device.screenHeight)"),
                    .hostName: .string(device.name),
                ]
            ),
        ]
    }
}

public struct WatchDeviceCollector: SnapshotCollector {
    public let identifier: CollectorID = "watchos.device.info"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    @MainActor
    public func collect(context _: CollectionContext) async throws -> WatchDeviceSnapshot {
        let device = WKInterfaceDevice.current()
        return WatchDeviceSnapshot(
            device: .init(
                name: device.name,
                model: device.model,
                systemVersion: device.systemVersion,
                screenWidth: Int(device.screenBounds.width * device.screenScale),
                screenHeight: Int(device.screenBounds.height * device.screenScale),
                waterResistanceDepth: Int(device.waterResistanceRating == .wr50 ? 50 : 0)
            )
        )
    }
}

public struct WatchBatterySnapshot: CollectedSection {
    public let level: Double
    public let state: String
    public let isAvailable: Bool

    public init(level: Double, state: String, isAvailable: Bool) {
        self.level = level
        self.state = state
        self.isAvailable = isAvailable
    }

    public static let schema = SectionSchema(
        capability: "power.battery",
        displayName: "Battery",
        summary: "Charge level and charging state.",
        category: .power,
        symbol: "battery.100",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .battery,
                singularName: "Battery",
                pluralName: "Battery",
                symbol: "battery.100",
                additionSeverity: .informational,
                removalSeverity: .notable,
                properties: [
                    PropertyDescriptor(
                        key: .batteryLevel,
                        displayName: "Charge",
                        unit: .percent,
                        comparison: .numeric(tolerance: 0.05),
                        severity: .informational,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .batteryState,
                        displayName: "State",
                        severity: .informational,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                ]
            ),
        ],
        displayOrder: 25
    )

    public var status: CollectionStatus {
        isAvailable ? .collected : .unavailable
    }

    public var entities: [SnapshotEntity] {
        guard isAvailable else { return [] }
        return [
            SnapshotEntity(
                kind: .battery,
                id: "internal",
                displayName: "Battery",
                subtitle: state,
                properties: [
                    .batteryLevel: .percentage(level),
                    .batteryState: .string(state),
                ]
            ),
        ]
    }
}

public struct WatchBatteryCollector: SnapshotCollector {
    public let identifier: CollectorID = "watchos.power.battery"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    @MainActor
    public func collect(context _: CollectionContext) async throws -> WatchBatterySnapshot {
        let device = WKInterfaceDevice.current()
        let wasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasEnabled }
        try? await Task.sleep(for: .milliseconds(120))

        let level = device.batteryLevel
        return WatchBatterySnapshot(
            level: level < 0 ? 0 : Double(level),
            state: Self.describe(device.batteryState),
            isAvailable: level >= 0
        )
    }

    static func describe(_ state: WKInterfaceDeviceBatteryState) -> String {
        switch state {
        case .charging: "Charging"
        case .full: "Full"
        case .unplugged: "On battery"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }
}

/// Everything Diffuse can observe on watchOS.
///
/// Four capabilities, not twelve. The Watch app exists to answer "what
/// changed" at a glance, and pretending it can enumerate applications or
/// developer tools would be dishonest rather than useful.
public struct WatchCapabilityRegistry: CapabilityRegistry {
    public let platform: Platform = .watchOS
    public let capabilities: [AnyCapability]

    public init() {
        capabilities = [
            AnyCapability(
                BasicCapability(
                    metadata: .describing(
                        WatchDeviceSnapshot.self,
                        summary: "Watch model and system version.",
                        collectionDescription: "Reads the watch model, system version, screen size and "
                            + "device name from WatchKit.",
                        platforms: [.watchOS],
                        cost: .low
                    ),
                    collector: { WatchDeviceCollector() }
                )
            ),
            AnyCapability(
                BasicCapability(
                    metadata: .describing(
                        WatchBatterySnapshot.self,
                        summary: "Charge level and charging state.",
                        collectionDescription: "Reads the battery charge level and charging state from WatchKit.",
                        platforms: [.watchOS],
                        cost: .low
                    ),
                    collector: { WatchBatteryCollector() }
                )
            ),
            SystemInfoCollector.capability(platforms: [.watchOS]),
            StorageCollector.capability(platforms: [.watchOS], enumeratesAllVolumes: false),
            NetworkPathCollector.capability(platforms: [.watchOS]),
        ]
        .sorted { $0.id < $1.id }
    }
}

public extension WatchCapabilityRegistry {
    static func makeService(
        storeDirectory: URL,
        installIdentifier: String,
        appVersion: SemanticVersion = "1.0.0"
    ) -> SnapshotService {
        let registry = WatchCapabilityRegistry()
        let catalog = CapabilityCatalog(
            registry: registry,
            enablementStore: UserDefaultsEnablementStore(key: "diffuse.enabledCapabilities")
        )
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: installIdentifier),
            platform: .watchOS,
            appVersion: appVersion
        )
        return SnapshotService(
            coordinator: coordinator,
            store: FileSnapshotStore(directory: storeDirectory),
            catalog: catalog,
            // A watch keeps far less history: it is a glance surface, and
            // its storage is scarce.
            retentionPolicy: RetentionPolicy(age: .days(30), maximumBytes: 32 * 1024 * 1024)
        )
    }
}

#endif
