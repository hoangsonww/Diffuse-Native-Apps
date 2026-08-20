import DiffuseCapabilities
import DiffuseModels
import Foundation

public struct StorageSnapshot: CollectedSection {
    public struct Volume: Sendable {
        public var identifier: String
        public var name: String
        public var path: String
        public var totalCapacity: Int64
        public var availableCapacity: Int64
        public var format: String?
        public var isRemovable: Bool
        public var isInternal: Bool

        public init(
            identifier: String,
            name: String,
            path: String,
            totalCapacity: Int64,
            availableCapacity: Int64,
            format: String? = nil,
            isRemovable: Bool = false,
            isInternal: Bool = true
        ) {
            self.identifier = identifier
            self.name = name
            self.path = path
            self.totalCapacity = totalCapacity
            self.availableCapacity = availableCapacity
            self.format = format
            self.isRemovable = isRemovable
            self.isInternal = isInternal
        }
    }

    public let volumes: [Volume]
    public let diagnostics: [Diagnostic]

    public init(volumes: [Volume], diagnostics: [Diagnostic] = []) {
        self.volumes = volumes
        self.diagnostics = diagnostics
    }

    public static let schema = SectionSchema(
        capability: "storage.volumes",
        displayName: "Storage",
        summary: "Mounted volumes and how much space is left on them.",
        category: .storage,
        symbol: "internaldrive",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .volume,
                singularName: "Volume",
                pluralName: "Volumes",
                symbol: "internaldrive",
                summary: "A mounted filesystem.",
                additionSeverity: .significant,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .availableCapacity,
                        displayName: "Free space",
                        summary: "Free space drifts constantly, so only a change of more than 1% is reported.",
                        unit: .bytes,
                        comparison: .relative(tolerance: 0.01),
                        severity: .informational,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .usedCapacity,
                        displayName: "Used",
                        unit: .bytes,
                        comparison: .relative(tolerance: 0.01),
                        severity: .informational,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .totalCapacity,
                        displayName: "Capacity",
                        unit: .bytes,
                        comparison: .relative(tolerance: 0.001),
                        severity: .significant,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .volumeFormat,
                        displayName: "Format",
                        severity: .significant,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .isRemovable,
                        displayName: "Removable",
                        severity: .notable,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .installPath,
                        displayName: "Mount point",
                        unit: .path,
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 5
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: .availableCapacity,
                displayName: "Total free space",
                unit: .bytes,
                comparison: .relative(tolerance: 0.01),
                severity: .informational
            ),
        ],
        displayOrder: 40
    )

    public var attributes: [PropertyKey: PropertyValue] {
        [.availableCapacity: .bytes(volumes.reduce(0) { $0 + $1.availableCapacity })]
    }

    public var status: CollectionStatus {
        volumes.isEmpty ? .partial : .collected
    }

    public var entities: [SnapshotEntity] {
        volumes.map { volume in
            SnapshotEntity(
                kind: .volume,
                id: volume.identifier,
                displayName: volume.name,
                subtitle: volume.isRemovable ? "Removable" : (volume.isInternal ? "Internal" : "External"),
                properties: [
                    .availableCapacity: .bytes(volume.availableCapacity),
                    .totalCapacity: .bytes(volume.totalCapacity),
                    .usedCapacity: .bytes(max(volume.totalCapacity - volume.availableCapacity, 0)),
                    .volumeFormat: volume.format.map { PropertyValue.string($0) } ?? .absent,
                    .isRemovable: .boolean(volume.isRemovable),
                    .installPath: .path(volume.path),
                ],
                tags: volume.isRemovable ? ["removable"] : ["internal"]
            )
        }
    }
}

/// Reads mounted volume capacities.
///
/// On macOS this enumerates every mounted volume. On iOS, iPadOS and watchOS
/// the sandbox only exposes the container's volume, so the collector reports
/// one entry rather than pretending otherwise.
public struct StorageCollector: SnapshotCollector {
    public let identifier: CollectorID = "shared.storage.volumes"
    public let version: SemanticVersion = "1.0.0"

    private let enumeratesAllVolumes: Bool

    public init(enumeratesAllVolumes: Bool = false) {
        self.enumeratesAllVolumes = enumeratesAllVolumes
    }

    public func collect(context _: CollectionContext) async throws -> StorageSnapshot {
        var keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeLocalizedFormatDescriptionKey,
        ]
        #if !os(watchOS) && !os(tvOS)
        keys.append(.volumeAvailableCapacityForImportantUsageKey)
        #endif

        var urls: [URL] = []
        if enumeratesAllVolumes,
           let mounted = FileManager.default.mountedVolumeURLs(
               includingResourceValuesForKeys: keys,
               options: [.skipHiddenVolumes]
           ) {
            urls = mounted
        } else {
            urls = [URL(fileURLWithPath: NSHomeDirectory())]
        }

        var volumes: [StorageSnapshot.Volume] = []
        var diagnostics: [Diagnostic] = []

        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                let total = Int64(values.volumeTotalCapacity ?? 0)
                guard total > 0 else { continue }

                // `importantUsage` is the number a user recognises as "free
                // space" because it accounts for purgeable content the system
                // would evict on demand. watchOS and tvOS do not expose it, so
                // they fall back to the raw figure.
                var available = Int64(values.volumeAvailableCapacity ?? 0)
                #if !os(watchOS) && !os(tvOS)
                if let important = values.volumeAvailableCapacityForImportantUsage {
                    available = important
                }
                #endif

                volumes.append(
                    StorageSnapshot.Volume(
                        identifier: values.volumeUUIDString ?? url.path,
                        name: values.volumeName ?? url.lastPathComponent,
                        path: url.path,
                        totalCapacity: total,
                        availableCapacity: available,
                        format: values.volumeLocalizedFormatDescription,
                        isRemovable: values.volumeIsRemovable ?? false,
                        isInternal: values.volumeIsInternal ?? true
                    )
                )
            } catch {
                diagnostics.append(
                    .warning("Could not read volume at \(url.lastPathComponent)", detail: error.localizedDescription)
                )
            }
        }

        return StorageSnapshot(
            volumes: volumes.sorted { $0.identifier < $1.identifier },
            diagnostics: diagnostics
        )
    }
}

public extension StorageCollector {
    static func capability(platforms: Set<Platform>, enumeratesAllVolumes: Bool) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                StorageSnapshot.self,
                summary: "How much space is left, and on which volumes.",
                collectionDescription: enumeratesAllVolumes
                    ? "Enumerates mounted volumes and reads each one's name, format, total capacity and free space. "
                    + "No file names or contents are read."
                    : "Reads the capacity and free space of the volume this app's container lives on. "
                    + "No file names or contents are read.",
                platforms: platforms,
                cost: .low
            ),
            collector: { StorageCollector(enumeratesAllVolumes: enumeratesAllVolumes) }
        ).erased
    }
}
