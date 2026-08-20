#if os(macOS)

import DiffuseCapabilities
import DiffuseCore
import DiffuseDeveloperTools
import DiffuseModels
import DiffuseStorage
import Foundation

/// Everything Diffuse can observe on macOS.
///
/// This list is the *only* compile-time commitment the Mac app makes.
/// Adding a capability means writing a collector and appending one line
/// here; nothing else in the app, the storage layer, the diff engine or the
/// UI needs to know it happened.
public struct MacCapabilityRegistry: CapabilityRegistry {
    public let platform: Platform = .macOS
    public let capabilities: [AnyCapability]

    public init(
        watchedRepositoryPaths: @escaping @Sendable () -> [String] = { [] },
        toolAdapters: [ToolAdapter] = BuiltInToolAdapters.all,
        processRunner: @escaping @Sendable () -> any ProcessRunning = { SystemProcessRunner() }
    ) {
        capabilities = [
            SystemInfoCollector.capability(platforms: [.macOS]),
            MacHardwareCollector.capability,
            MacDisplayCollector.capability,
            MacPowerCollector.capability,
            NetworkInterfaceCollector.capability(platforms: [.macOS]),
            NetworkPathCollector.capability(platforms: [.macOS]),
            MacWiFiCollector.capability,
            StorageCollector.capability(platforms: [.macOS], enumeratesAllVolumes: true),
            MacApplicationsCollector.capability,
            MacProcessCollector.capability(runner: processRunner),
            MacDeveloperToolsCollector.capability(adapters: toolAdapters, runner: processRunner),
            MacGitCollector.capability(repositoryPaths: watchedRepositoryPaths, runner: processRunner),
        ]
        .sorted { $0.id < $1.id }
    }
}

public extension MacCapabilityRegistry {
    /// Builds the fully wired service the Mac app runs on.
    static func makeService(
        storeDirectory: URL,
        installIdentifier: String,
        watchedRepositoryPaths: @escaping @Sendable () -> [String],
        appVersion: SemanticVersion = "1.0.0"
    ) -> SnapshotService {
        let registry = MacCapabilityRegistry(watchedRepositoryPaths: watchedRepositoryPaths)
        let catalog = CapabilityCatalog(
            registry: registry,
            enablementStore: UserDefaultsEnablementStore(key: "diffuse.enabledCapabilities")
        )
        let coordinator = SnapshotCoordinator(
            catalog: catalog,
            deviceProvider: ProcessInfoDeviceIdentityProvider(installIdentifier: installIdentifier),
            platform: .macOS,
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
