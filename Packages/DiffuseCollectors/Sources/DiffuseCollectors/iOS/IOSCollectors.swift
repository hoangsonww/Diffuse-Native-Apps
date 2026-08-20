#if os(iOS)

import DiffuseCapabilities
import DiffuseCore
import DiffuseModels
import DiffuseStorage
import Foundation
import UIKit

// MARK: - Device

public struct IOSDeviceSnapshot: CollectedSection {
    public struct Device: Sendable {
        public var name: String
        public var model: String
        public var modelIdentifier: String
        public var systemName: String
        public var systemVersion: String
        public var idiom: String
        public var isSimulator: Bool
    }

    public let device: Device

    public init(device: Device) {
        self.device = device
    }

    public static let schema = SectionSchema(
        capability: "device.info",
        displayName: "Device",
        summary: "What this device is and which system version it runs.",
        category: .hardware,
        symbol: "iphone",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .machine,
                singularName: "Device",
                pluralName: "Device",
                symbol: "iphone",
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
                        key: .modelIdentifier,
                        displayName: "Model identifier",
                        severity: .critical,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .osVersion,
                        displayName: "System version",
                        unit: .version,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(key: "idiom", displayName: "Idiom", severity: .significant, displayOrder: 3),
                    PropertyDescriptor(
                        key: .hostName,
                        displayName: "Device name",
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 4
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
                id: device.modelIdentifier,
                displayName: device.model,
                subtitle: "\(device.systemName) \(device.systemVersion)",
                properties: [
                    .model: .string(device.model),
                    .modelIdentifier: .identifier(device.modelIdentifier),
                    .osVersion: SemanticVersion(device.systemVersion).map { PropertyValue.version($0) }
                        ?? .string(device.systemVersion),
                    "idiom": .string(device.idiom),
                    .hostName: .string(device.name),
                ],
                tags: device.isSimulator ? ["simulator"] : []
            ),
        ]
    }
}

public struct IOSDeviceCollector: SnapshotCollector {
    public let identifier: CollectorID = "ios.device.info"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    @MainActor
    public func collect(context _: CollectionContext) async throws -> IOSDeviceSnapshot {
        let device = UIDevice.current
        return IOSDeviceSnapshot(
            device: .init(
                name: device.name,
                model: device.model,
                modelIdentifier: Self.modelIdentifier(),
                systemName: device.systemName,
                systemVersion: device.systemVersion,
                idiom: Self.describe(device.userInterfaceIdiom),
                isSimulator: Self.isSimulator
            )
        )
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The simulator reports the host Mac's `hw.machine`, so the simulated
    /// device identifier comes from the environment instead.
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    static func describe(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .mac: "Mac"
        case .tv: "TV"
        case .carPlay: "CarPlay"
        case .vision: "Vision"
        case .unspecified: "Unspecified"
        @unknown default: "Unknown"
        }
    }
}

public extension IOSDeviceCollector {
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                IOSDeviceSnapshot.self,
                summary: "Model, system version and device name.",
                collectionDescription: "Reads the device model and identifier, the system version and the "
                    + "device name from UIDevice. No advertising or vendor identifier is read.",
                platforms: platforms,
                cost: .low
            ),
            collector: { IOSDeviceCollector() }
        ).erased
    }
}

// MARK: - Battery

public struct IOSBatterySnapshot: CollectedSection {
    public let level: Double
    public let state: String
    public let lowPowerMode: Bool
    public let isAvailable: Bool

    public init(level: Double, state: String, lowPowerMode: Bool, isAvailable: Bool) {
        self.level = level
        self.state = state
        self.lowPowerMode = lowPowerMode
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
                        summary: "Battery level is expected to move, so it stays informational unless it "
                            + "swings by a quarter of the battery.",
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
                    PropertyDescriptor(
                        key: .lowPowerMode,
                        displayName: "Low Power Mode",
                        severity: .notable,
                        displayOrder: 2
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
                    .lowPowerMode: .boolean(lowPowerMode),
                ]
            ),
        ]
    }
}

public struct IOSBatteryCollector: SnapshotCollector {
    public let identifier: CollectorID = "ios.power.battery"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    @MainActor
    public func collect(context _: CollectionContext) async throws -> IOSBatterySnapshot {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasEnabled }

        // UIKit needs a run loop turn after enabling monitoring before it
        // reports anything other than `.unknown`.
        try? await Task.sleep(for: .milliseconds(120))

        let level = device.batteryLevel
        return IOSBatterySnapshot(
            level: level < 0 ? 0 : Double(level),
            state: Self.describe(device.batteryState),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isAvailable: level >= 0
        )
    }

    static func describe(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: "Charging"
        case .full: "Full"
        case .unplugged: "On battery"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }
}

public extension IOSBatteryCollector {
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                IOSBatterySnapshot.self,
                summary: "Charge level, charging state and Low Power Mode.",
                collectionDescription: "Reads the battery charge level and charging state from UIDevice, "
                    + "plus whether Low Power Mode is on.",
                platforms: platforms,
                cost: .low
            ),
            collector: { IOSBatteryCollector() }
        ).erased
    }
}

// MARK: - Screen

public struct IOSScreenSnapshot: CollectedSection {
    public struct Screen: Sendable {
        public var width: Int
        public var height: Int
        public var scale: Double
        public var brightness: Double
        public var maximumFramesPerSecond: Int
    }

    public let screen: Screen

    public init(screen: Screen) {
        self.screen = screen
    }

    public static let schema = SectionSchema(
        capability: "display.screen",
        displayName: "Screen",
        summary: "Screen size, scale, refresh ceiling and brightness.",
        category: .display,
        symbol: "rectangle.on.rectangle",
        privacy: .public,
        entityKinds: [
            EntityKindDescriptor(
                kind: .screen,
                singularName: "Screen",
                pluralName: "Screens",
                symbol: "rectangle.on.rectangle",
                additionSeverity: .significant,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .resolution,
                        displayName: "Size",
                        unit: .pixels,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .scaleFactor,
                        displayName: "Scale",
                        comparison: .numeric(tolerance: 0.01),
                        severity: .significant,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .refreshRate,
                        displayName: "Max refresh",
                        unit: .hertz,
                        comparison: .numeric(tolerance: 1),
                        severity: .notable,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .brightness,
                        displayName: "Brightness",
                        summary: "Brightness changes constantly with ambient light, so it is informational.",
                        unit: .percent,
                        comparison: .numeric(tolerance: 0.15),
                        severity: .informational,
                        displayOrder: 3
                    ),
                ]
            ),
        ],
        displayOrder: 21
    )

    public var entities: [SnapshotEntity] {
        [
            SnapshotEntity(
                kind: .screen,
                id: "main",
                displayName: "Main screen",
                subtitle: "\(screen.width) × \(screen.height)",
                properties: [
                    .resolution: .string("\(screen.width) × \(screen.height)"),
                    .scaleFactor: .double(screen.scale),
                    .refreshRate: .integer(Int64(screen.maximumFramesPerSecond)),
                    .brightness: .percentage(screen.brightness),
                ]
            ),
        ]
    }
}

public struct IOSScreenCollector: SnapshotCollector {
    public let identifier: CollectorID = "ios.display.screen"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    @MainActor
    public func collect(context _: CollectionContext) async throws -> IOSScreenSnapshot {
        let screen = UIScreen.main
        return IOSScreenSnapshot(
            screen: .init(
                width: Int(screen.nativeBounds.width),
                height: Int(screen.nativeBounds.height),
                scale: Double(screen.nativeScale),
                brightness: Double(screen.brightness),
                maximumFramesPerSecond: screen.maximumFramesPerSecond
            )
        )
    }
}

public extension IOSScreenCollector {
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                IOSScreenSnapshot.self,
                summary: "Screen geometry and brightness.",
                collectionDescription: "Reads the main screen's pixel dimensions, scale factor, maximum "
                    + "refresh rate and current brightness. Nothing on screen is captured.",
                platforms: platforms,
                cost: .low
            ),
            collector: { IOSScreenCollector() }
        ).erased
    }
}

// MARK: - Registry

/// Everything Diffuse can observe on iOS and iPadOS.
///
/// Deliberately shorter than the Mac list. iOS does not expose process
/// tables, installed applications or a developer toolchain, and Diffuse
/// does not pretend otherwise — the platforms differ, and the product says
/// so rather than showing a screen full of "not supported".
public struct IOSCapabilityRegistry: CapabilityRegistry {
    public let platform: Platform
    public let capabilities: [AnyCapability]

    public init(platform: Platform = .iOS) {
        self.platform = platform
        let platforms: Set<Platform> = [platform]
        capabilities = [
            IOSDeviceCollector.capability(platforms: platforms),
            SystemInfoCollector.capability(platforms: platforms),
            IOSBatteryCollector.capability(platforms: platforms),
            IOSScreenCollector.capability(platforms: platforms),
            StorageCollector.capability(platforms: platforms, enumeratesAllVolumes: false),
            NetworkInterfaceCollector.capability(platforms: platforms),
            NetworkPathCollector.capability(platforms: platforms),
        ]
        .sorted { $0.id < $1.id }
    }
}

public extension IOSCapabilityRegistry {
    static func makeService(
        storeDirectory: URL,
        installIdentifier: String,
        platform: Platform = .iOS,
        appVersion: SemanticVersion = "1.0.0"
    ) -> SnapshotService {
        let registry = IOSCapabilityRegistry(platform: platform)
        let catalog = CapabilityCatalog(
            registry: registry,
            enablementStore: UserDefaultsEnablementStore(key: "diffuse.enabledCapabilities")
        )
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: installIdentifier),
            platform: platform,
            appVersion: appVersion
        )
        return SnapshotService(
            coordinator: coordinator,
            store: FileSnapshotStore(directory: storeDirectory),
            catalog: catalog
        )
    }
}

#endif
