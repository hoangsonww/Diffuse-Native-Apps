import DiffuseModels

/// Property keys shared by more than one collector.
///
/// Not an exhaustive registry — collectors are free to invent keys, and the
/// schema they publish is what gives those keys meaning. These exist purely so
/// that "operating system version" is spelled the same way by the macOS, iOS
/// and watchOS system collectors, which makes cross-platform snapshots read
/// consistently.
public extension PropertyKey {
    // System
    static let osName: PropertyKey = "os.name"
    static let osVersion: PropertyKey = "os.version"
    static let osBuild: PropertyKey = "os.build"
    static let kernelVersion: PropertyKey = "kernel.version"
    static let uptime: PropertyKey = "uptime"
    static let bootedAt: PropertyKey = "bootedAt"
    static let hostName: PropertyKey = "hostName"
    static let locale: PropertyKey = "locale"
    static let timeZone: PropertyKey = "timeZone"
    static let thermalState: PropertyKey = "thermalState"
    static let lowPowerMode: PropertyKey = "lowPowerMode"

    // Hardware
    static let model: PropertyKey = "model"
    static let modelIdentifier: PropertyKey = "modelIdentifier"
    static let architecture: PropertyKey = "architecture"
    static let processor: PropertyKey = "processor"
    static let coreCount: PropertyKey = "coreCount"
    static let performanceCoreCount: PropertyKey = "performanceCoreCount"
    static let efficiencyCoreCount: PropertyKey = "efficiencyCoreCount"
    static let physicalMemory: PropertyKey = "physicalMemory"

    // Display
    static let resolution: PropertyKey = "resolution"
    static let refreshRate: PropertyKey = "refreshRate"
    static let scaleFactor: PropertyKey = "scaleFactor"
    static let isMain: PropertyKey = "isMain"
    static let isBuiltIn: PropertyKey = "isBuiltIn"
    static let colorSpace: PropertyKey = "colorSpace"
    static let brightness: PropertyKey = "brightness"

    // Power
    static let batteryLevel: PropertyKey = "batteryLevel"
    static let batteryState: PropertyKey = "batteryState"
    static let isCharging: PropertyKey = "isCharging"
    static let cycleCount: PropertyKey = "cycleCount"
    static let batteryHealth: PropertyKey = "batteryHealth"
    static let timeToEmpty: PropertyKey = "timeToEmpty"
    static let powerSource: PropertyKey = "powerSource"

    // Network
    static let interfaceName: PropertyKey = "interfaceName"
    static let interfaceType: PropertyKey = "interfaceType"
    static let isActive: PropertyKey = "isActive"
    static let ipv4Address: PropertyKey = "ipv4Address"
    static let ipv6Address: PropertyKey = "ipv6Address"
    static let ssid: PropertyKey = "ssid"
    static let signalStrength: PropertyKey = "signalStrength"
    static let channel: PropertyKey = "channel"
    static let security: PropertyKey = "security"
    static let isExpensive: PropertyKey = "isExpensive"
    static let isConstrained: PropertyKey = "isConstrained"
    static let pathStatus: PropertyKey = "pathStatus"
    static let usesVPN: PropertyKey = "usesVPN"

    // Storage
    static let totalCapacity: PropertyKey = "totalCapacity"
    static let availableCapacity: PropertyKey = "availableCapacity"
    static let usedCapacity: PropertyKey = "usedCapacity"
    static let volumeFormat: PropertyKey = "volumeFormat"
    static let isRemovable: PropertyKey = "isRemovable"
    static let isEncrypted: PropertyKey = "isEncrypted"

    // Software
    static let version: PropertyKey = "version"
    static let buildNumber: PropertyKey = "buildNumber"
    static let bundleIdentifier: PropertyKey = "bundleIdentifier"
    static let installPath: PropertyKey = "installPath"
    static let executablePath: PropertyKey = "executablePath"

    // Development
    static let branch: PropertyKey = "branch"
    static let commit: PropertyKey = "commit"
    static let isDirty: PropertyKey = "isDirty"
    static let modifiedFileCount: PropertyKey = "modifiedFileCount"
    static let untrackedFileCount: PropertyKey = "untrackedFileCount"
    static let aheadCount: PropertyKey = "aheadCount"
    static let behindCount: PropertyKey = "behindCount"
    static let remoteURL: PropertyKey = "remoteURL"
    static let repositoryPath: PropertyKey = "repositoryPath"

    // Processes
    static let processCount: PropertyKey = "processCount"
    static let memoryFootprint: PropertyKey = "memoryFootprint"
    static let cpuUsage: PropertyKey = "cpuUsage"
}

public extension EntityKind {
    static let system: EntityKind = "system"
    static let machine: EntityKind = "machine"
    static let display: EntityKind = "display"
    static let battery: EntityKind = "battery"
    static let networkInterface: EntityKind = "networkInterface"
    static let networkPath: EntityKind = "networkPath"
    static let wifiNetwork: EntityKind = "wifiNetwork"
    static let volume: EntityKind = "volume"
    static let application: EntityKind = "application"
    static let developerTool: EntityKind = "developerTool"
    static let gitRepository: EntityKind = "gitRepository"
    static let process: EntityKind = "process"
    static let screen: EntityKind = "screen"
}
