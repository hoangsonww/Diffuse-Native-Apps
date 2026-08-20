#if os(macOS)

import DiffuseCapabilities
import DiffuseModels
import Foundation
import IOKit.ps

public struct MacPowerSnapshot: CollectedSection {
    public struct Battery: Sendable {
        public var name: String
        public var level: Double
        public var isCharging: Bool
        public var powerSource: String
        public var cycleCount: Int?
        public var health: String?
        public var timeToEmpty: TimeInterval?
    }

    public let battery: Battery?
    public let diagnostics: [Diagnostic]

    public init(battery: Battery?, diagnostics: [Diagnostic] = []) {
        self.battery = battery
        self.diagnostics = diagnostics
    }

    public static let schema = SectionSchema(
        capability: "power.battery",
        displayName: "Power",
        summary: "Battery level, charge state and which power source is in use.",
        category: .power,
        symbol: "battery.100",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .battery,
                singularName: "Battery",
                pluralName: "Batteries",
                symbol: "battery.100",
                additionSeverity: .notable,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .batteryLevel,
                        displayName: "Charge",
                        summary: "Battery level moves constantly, so it is informational and only reported "
                            + "when it moves by more than five percentage points.",
                        unit: .percent,
                        comparison: .numeric(tolerance: 0.05),
                        severity: .informational,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .powerSource,
                        displayName: "Power source",
                        severity: .notable,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .isCharging,
                        displayName: "Charging",
                        severity: .informational,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .cycleCount,
                        displayName: "Cycle count",
                        unit: .count,
                        comparison: .numeric(tolerance: 2),
                        severity: .informational,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .batteryHealth,
                        displayName: "Condition",
                        severity: .significant,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .timeToEmpty,
                        displayName: "Time remaining",
                        unit: .seconds,
                        comparison: .relative(tolerance: 0.2),
                        severity: .informational,
                        displayOrder: 5
                    ),
                ]
            ),
        ],
        displayOrder: 25
    )

    public var status: CollectionStatus {
        battery == nil ? .unavailable : .collected
    }

    public var entities: [SnapshotEntity] {
        guard let battery else { return [] }
        return [
            SnapshotEntity(
                kind: .battery,
                id: "internal",
                displayName: battery.name,
                subtitle: battery.powerSource,
                properties: [
                    .batteryLevel: .percentage(battery.level),
                    .powerSource: .string(battery.powerSource),
                    .isCharging: .boolean(battery.isCharging),
                    .cycleCount: battery.cycleCount.map { PropertyValue.integer(Int64($0)) } ?? .absent,
                    .batteryHealth: battery.health.map { PropertyValue.string($0) } ?? .absent,
                    .timeToEmpty: battery.timeToEmpty.map { PropertyValue.duration($0) } ?? .absent,
                ]
            ),
        ]
    }
}

/// Reads power state from IOKit.
///
/// Desktop Macs have no battery, which is a legitimate "unavailable" rather
/// than an error — the section records that and the snapshot succeeds.
public struct MacPowerCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.power.battery"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    public func collect(context _: CollectionContext) async throws -> MacPowerSnapshot {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return MacPowerSnapshot(battery: nil, diagnostics: [.info("No power sources reported")])
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                let type = description[kIOPSTypeKey] as? String,
                type == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let minutesToEmpty = description[kIOPSTimeToEmptyKey] as? Int

            return MacPowerSnapshot(
                battery: .init(
                    name: description[kIOPSNameKey] as? String ?? "Internal Battery",
                    level: maximum > 0 ? Double(current) / Double(maximum) : 0,
                    isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                    powerSource: description[kIOPSPowerSourceStateKey] as? String ?? "Unknown",
                    cycleCount: nil,
                    health: description["BatteryHealth"] as? String,
                    // IOKit reports -1 while it is still calculating.
                    timeToEmpty: minutesToEmpty.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil }
                )
            )
        }

        return MacPowerSnapshot(
            battery: nil,
            diagnostics: [.info("This Mac has no internal battery")]
        )
    }
}

public extension MacPowerCollector {
    static var capability: AnyCapability {
        BasicCapability(
            metadata: .describing(
                MacPowerSnapshot.self,
                summary: "Battery charge and power source.",
                collectionDescription: "Reads the internal battery's charge level, charging state, power "
                    + "source and reported condition from IOKit.",
                platforms: [.macOS],
                cost: .low
            ),
            availability: {
                guard
                    let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                    let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
                    !sources.isEmpty
                else {
                    return .unavailable(reason: "This Mac has no battery")
                }
                return .available
            },
            collector: { MacPowerCollector() }
        ).erased
    }
}

#endif
