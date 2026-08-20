import DiffuseModels
import Foundation

/// Deterministic snapshots used by fixtures, tests and SwiftUI previews.
///
/// Every value is fixed — no `Date()`, no `UUID()`, no environment lookups — so
/// the same call always produces the same bytes. That is what lets the golden
/// fixture suite detect an unintended change in diff behaviour by comparing
/// files, and it means all four apps get identical, meaningful previews.
public enum SampleData {
    /// A fixed reference point. Sunday 17 August 2026, 09:04 UTC.
    public static let baseDate = Date(timeIntervalSince1970: 1_787_130_240)

    public static let device = DeviceIdentity(
        id: "sample-device",
        name: "Sample MacBook Pro",
        model: "Mac15,3",
        systemName: "macOS",
        systemVersion: "26.0.0",
        architecture: "arm64"
    )

    // MARK: - Schemas

    public enum Schemas {
        public static let system = SectionSchema(
            capability: "system.info",
            displayName: "System",
            summary: "Operating system version, uptime and locale.",
            category: .system,
            symbol: "cpu",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "system",
                    singularName: "System",
                    pluralName: "System",
                    symbol: "cpu",
                    additionSeverity: .informational,
                    removalSeverity: .informational,
                    properties: [
                        PropertyDescriptor(
                            key: "os.name",
                            displayName: "Operating system",
                            severity: .critical,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "os.version",
                            displayName: "Version",
                            unit: .version,
                            severity: .significant,
                            isPrimary: true,
                            displayOrder: 1
                        ),
                        PropertyDescriptor(
                            key: "uptime",
                            displayName: "Uptime",
                            unit: .seconds,
                            comparison: .ignored,
                            severity: .informational,
                            displayOrder: 2
                        ),
                    ]
                ),
            ],
            displayOrder: 0
        )

        public static let network = SectionSchema(
            capability: "network.path",
            displayName: "Connectivity",
            summary: "How this device is reaching the network.",
            category: .network,
            symbol: "wifi",
            privacy: .sensitive,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "networkPath",
                    singularName: "Connection",
                    pluralName: "Connections",
                    symbol: "wifi",
                    additionSeverity: .notable,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(
                            key: "ssid",
                            displayName: "Network",
                            severity: .significant,
                            privacy: .sensitive,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "interfaceType",
                            displayName: "Connection",
                            severity: .significant,
                            isPrimary: true,
                            displayOrder: 1
                        ),
                        PropertyDescriptor(key: "usesVPN", displayName: "VPN", severity: .significant, displayOrder: 2),
                    ]
                ),
            ],
            displayOrder: 30
        )

        public static let storage = SectionSchema(
            capability: "storage.volumes",
            displayName: "Storage",
            summary: "Mounted volumes and free space.",
            category: .storage,
            symbol: "internaldrive",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "volume",
                    singularName: "Volume",
                    pluralName: "Volumes",
                    symbol: "internaldrive",
                    additionSeverity: .significant,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(
                            key: "availableCapacity",
                            displayName: "Free space",
                            unit: .bytes,
                            comparison: .relative(tolerance: 0.01),
                            severity: .informational,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "totalCapacity",
                            displayName: "Capacity",
                            unit: .bytes,
                            comparison: .relative(tolerance: 0.001),
                            severity: .significant,
                            displayOrder: 1
                        ),
                    ]
                ),
            ],
            displayOrder: 40
        )

        public static let developerTools = SectionSchema(
            capability: "development.tools",
            displayName: "Developer tools",
            summary: "Command line toolchains and their versions.",
            category: .development,
            symbol: "hammer",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "developerTool",
                    singularName: "Tool",
                    pluralName: "Tools",
                    symbol: "terminal",
                    additionSeverity: .significant,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(
                            key: "version",
                            displayName: "Version",
                            unit: .version,
                            severity: .significant,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "executablePath",
                            displayName: "Path",
                            unit: .path,
                            severity: .significant,
                            privacy: .sensitive,
                            displayOrder: 1
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

        public static let git = SectionSchema(
            capability: "development.git",
            displayName: "Git repositories",
            summary: "Branch and working tree state.",
            category: .development,
            symbol: "arrow.triangle.branch",
            privacy: .sensitive,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "gitRepository",
                    singularName: "Repository",
                    pluralName: "Repositories",
                    symbol: "arrow.triangle.branch",
                    additionSeverity: .notable,
                    removalSeverity: .notable,
                    properties: [
                        PropertyDescriptor(
                            key: "branch",
                            displayName: "Branch",
                            severity: .significant,
                            privacy: .sensitive,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "commit",
                            displayName: "Commit",
                            severity: .notable,
                            privacy: .sensitive,
                            isPrimary: true,
                            displayOrder: 1
                        ),
                        PropertyDescriptor(
                            key: "modifiedFileCount",
                            displayName: "Modified files",
                            unit: .count,
                            comparison: .exact,
                            severity: .informational,
                            displayOrder: 2
                        ),
                    ]
                ),
            ],
            displayOrder: 61
        )

        public static let display = SectionSchema(
            capability: "display.configuration",
            displayName: "Displays",
            summary: "Connected displays and their configuration.",
            category: .display,
            symbol: "display",
            privacy: .public,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "display",
                    singularName: "Display",
                    pluralName: "Displays",
                    symbol: "display",
                    additionSeverity: .significant,
                    removalSeverity: .significant,
                    properties: [
                        PropertyDescriptor(
                            key: "resolution",
                            displayName: "Resolution",
                            unit: .pixels,
                            severity: .significant,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "refreshRate",
                            displayName: "Refresh rate",
                            unit: .hertz,
                            comparison: .numeric(tolerance: 0.5),
                            severity: .notable,
                            isPrimary: true,
                            displayOrder: 1
                        ),
                    ]
                ),
            ],
            displayOrder: 20
        )

        public static let battery = SectionSchema(
            capability: "power.battery",
            displayName: "Battery",
            summary: "Charge level and charging state.",
            category: .power,
            symbol: "battery.100",
            privacy: .local,
            entityKinds: [
                EntityKindDescriptor(
                    kind: "battery",
                    singularName: "Battery",
                    pluralName: "Battery",
                    symbol: "battery.100",
                    additionSeverity: .informational,
                    removalSeverity: .notable,
                    properties: [
                        PropertyDescriptor(
                            key: "batteryLevel",
                            displayName: "Charge",
                            unit: .percent,
                            comparison: .numeric(tolerance: 0.05),
                            severity: .informational,
                            isPrimary: true,
                            displayOrder: 0
                        ),
                        PropertyDescriptor(
                            key: "batteryState",
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
    }

    // MARK: - Section builders

    static func section(
        _ schema: SectionSchema,
        collector: String,
        at date: Date,
        status: CollectionStatus = .collected,
        entities: [SnapshotEntity],
        attributes: [PropertyKey: PropertyValue] = [:],
        diagnostics: [Diagnostic] = []
    ) -> SnapshotSection {
        SnapshotSection(
            capability: schema.capability,
            collector: CollectorID(collector),
            collectorVersion: "1.0.0",
            collectedAt: date,
            duration: 0.012,
            status: status,
            schema: schema,
            entities: entities,
            attributes: attributes,
            diagnostics: diagnostics
        )
    }

    static func systemSection(at date: Date, osVersion: String, uptime: TimeInterval) -> SnapshotSection {
        section(
            Schemas.system,
            collector: "sample.system",
            at: date,
            entities: [
                SnapshotEntity(
                    kind: "system",
                    id: "primary",
                    displayName: "macOS",
                    subtitle: osVersion,
                    properties: [
                        "os.name": .string("macOS"),
                        "os.version": .version(SemanticVersion(osVersion) ?? "26.0.0"),
                        "uptime": .duration(uptime),
                    ]
                ),
            ]
        )
    }

    static func networkSection(at date: Date, ssid: String, type: String, vpn: Bool) -> SnapshotSection {
        section(
            Schemas.network,
            collector: "sample.network",
            at: date,
            entities: [
                SnapshotEntity(
                    kind: "networkPath",
                    id: "default",
                    displayName: ssid,
                    subtitle: type,
                    properties: [
                        "ssid": .string(ssid),
                        "interfaceType": .string(type),
                        "usesVPN": .boolean(vpn),
                    ],
                    tags: vpn ? ["vpn"] : []
                ),
            ]
        )
    }

    static func storageSection(at date: Date, free: Int64, total: Int64 = 1_000_000_000_000) -> SnapshotSection {
        section(
            Schemas.storage,
            collector: "sample.storage",
            at: date,
            entities: [
                SnapshotEntity(
                    kind: "volume",
                    id: "macintosh-hd",
                    displayName: "Macintosh HD",
                    subtitle: "Internal",
                    properties: [
                        "availableCapacity": .bytes(free),
                        "totalCapacity": .bytes(total),
                    ]
                ),
            ]
        )
    }

    static func toolsSection(at date: Date, tools: [(String, String, String)]) -> SnapshotSection {
        section(
            Schemas.developerTools,
            collector: "sample.tools",
            at: date,
            entities: tools.map { id, name, version in
                SnapshotEntity(
                    kind: "developerTool",
                    id: id,
                    displayName: name,
                    subtitle: version,
                    properties: [
                        "version": .version(SemanticVersion(version) ?? "0.0.0"),
                        "executablePath": .path("/opt/homebrew/bin/\(id)"),
                    ]
                )
            },
            attributes: ["toolCount": .integer(Int64(tools.count))]
        )
    }

    static func gitSection(at date: Date, branch: String, commit: String, modified: Int) -> SnapshotSection {
        section(
            Schemas.git,
            collector: "sample.git",
            at: date,
            entities: [
                SnapshotEntity(
                    identity: EntityIdentity(kind: "gitRepository", value: "~/dev/relayone"),
                    displayName: "relayone",
                    subtitle: branch,
                    properties: [
                        "branch": .string(branch),
                        "commit": .identifier(commit),
                        "modifiedFileCount": .integer(Int64(modified)),
                    ]
                ),
            ]
        )
    }

    static func displaySection(at date: Date, includesExternal: Bool) -> SnapshotSection {
        var entities = [
            SnapshotEntity(
                kind: "display",
                id: "builtin-0-0",
                displayName: "Built-in Display",
                subtitle: "3456 × 2234",
                properties: [
                    "resolution": .string("3456 × 2234"),
                    "refreshRate": .double(120),
                ],
                tags: ["built-in"]
            ),
        ]
        if includesExternal {
            entities.append(
                SnapshotEntity(
                    kind: "display",
                    id: "apple-9243-1",
                    displayName: "Studio Display",
                    subtitle: "5120 × 2880",
                    properties: [
                        "resolution": .string("5120 × 2880"),
                        "refreshRate": .double(60),
                    ],
                    tags: ["external"]
                )
            )
        }
        return section(Schemas.display, collector: "sample.display", at: date, entities: entities)
    }

    static func batterySection(at date: Date, level: Double, state: String) -> SnapshotSection {
        section(
            Schemas.battery,
            collector: "sample.battery",
            at: date,
            entities: [
                SnapshotEntity(
                    kind: "battery",
                    id: "internal",
                    displayName: "Battery",
                    subtitle: state,
                    properties: [
                        "batteryLevel": .percentage(level),
                        "batteryState": .string(state),
                    ]
                ),
            ]
        )
    }

    // MARK: - Snapshots

    /// The reference "before" snapshot.
    public static var macBaseline: Snapshot {
        Snapshot(
            id: "sample-mac-baseline",
            capturedAt: baseDate,
            platform: .macOS,
            device: device,
            origin: .scheduled,
            label: "Morning snapshot",
            sections: [
                systemSection(at: baseDate, osVersion: "26.0.0", uptime: 82800),
                displaySection(at: baseDate, includesExternal: true),
                batterySection(at: baseDate, level: 0.82, state: "On battery"),
                networkSection(at: baseDate, ssid: "Home", type: "Wi-Fi", vpn: false),
                storageSection(at: baseDate, free: 218_000_000_000),
                toolsSection(at: baseDate, tools: [
                    ("node", "Node.js", "24.5.0"),
                    ("git", "Git", "2.46.0"),
                    ("docker", "Docker", "27.2.0"),
                ]),
                gitSection(at: baseDate, branch: "feature/auth", commit: "a81e21c4", modified: 2),
            ],
            metadata: SnapshotMetadata(appVersion: "1.0.0", collectionDuration: 0.42)
        )
    }

    /// The reference "after" snapshot: a Node upgrade, a move to the office, a
    /// branch switch, a disconnected display and normal storage drift.
    public static var macAfterWorkday: Snapshot {
        let date = baseDate.addingTimeInterval(9180) // 11:37
        return Snapshot(
            id: "sample-mac-after-workday",
            capturedAt: date,
            platform: .macOS,
            device: device,
            origin: .manual,
            label: "After the Node upgrade",
            sections: [
                systemSection(at: date, osVersion: "26.0.0", uptime: 91980),
                displaySection(at: date, includesExternal: false),
                batterySection(at: date.addingTimeInterval(30), level: 0.61, state: "Charging"),
                networkSection(at: date.addingTimeInterval(120), ssid: "Office", type: "Wi-Fi", vpn: true),
                storageSection(at: date.addingTimeInterval(180), free: 191_000_000_000),
                toolsSection(at: date.addingTimeInterval(240), tools: [
                    ("node", "Node.js", "24.6.0"),
                    ("git", "Git", "2.46.0"),
                    ("rustc", "Rust", "1.81.0"),
                ]),
                gitSection(at: date.addingTimeInterval(300), branch: "feature/webrtc", commit: "c31a8207", modified: 5),
            ],
            metadata: SnapshotMetadata(appVersion: "1.0.0", collectionDuration: 0.51)
        )
    }

    /// A snapshot where one collector could not run, used to exercise the
    /// isolation and status-change paths.
    public static var macWithPermissionProblem: Snapshot {
        let date = baseDate.addingTimeInterval(18360)
        var snapshot = macAfterWorkday
        snapshot = Snapshot(
            id: "sample-mac-permission-problem",
            capturedAt: date,
            platform: .macOS,
            device: device,
            origin: .scheduled,
            sections: snapshot.sections.map { section in
                guard section.capability == "network.path" else { return section }
                return SnapshotSection.placeholder(
                    capability: section.capability,
                    collector: section.collector,
                    schema: section.schema,
                    status: .permissionRequired,
                    at: date,
                    diagnostics: [.warning("Location Services is required to read the current network name")]
                )
            },
            metadata: SnapshotMetadata(appVersion: "1.0.0", collectionDuration: 0.33)
        )
        return snapshot
    }

    public static var iosBaseline: Snapshot {
        Snapshot(
            id: "sample-ios-baseline",
            capturedAt: baseDate,
            platform: .iOS,
            device: DeviceIdentity(
                id: "sample-iphone",
                name: "Sample iPhone",
                model: "iPhone17,1",
                systemName: "iOS",
                systemVersion: "26.0.0",
                architecture: "arm64"
            ),
            origin: .scheduled,
            label: "Morning snapshot",
            sections: [
                systemSection(at: baseDate, osVersion: "26.0.0", uptime: 340_000),
                batterySection(at: baseDate, level: 0.82, state: "On battery"),
                networkSection(at: baseDate, ssid: "Home", type: "Wi-Fi", vpn: false),
                storageSection(at: baseDate, free: 121_200_000_000, total: 256_000_000_000),
            ],
            metadata: SnapshotMetadata(appVersion: "1.0.0", collectionDuration: 0.18)
        )
    }

    public static var iosAfternoon: Snapshot {
        let date = baseDate.addingTimeInterval(18720)
        return Snapshot(
            id: "sample-ios-afternoon",
            capturedAt: date,
            platform: .iOS,
            device: iosBaseline.device,
            origin: .manual,
            sections: [
                systemSection(at: date, osVersion: "26.0.0", uptime: 358_720),
                batterySection(at: date, level: 0.61, state: "On battery"),
                networkSection(at: date, ssid: "Cellular", type: "Cellular", vpn: true),
                storageSection(at: date, free: 120_800_000_000, total: 256_000_000_000),
            ],
            metadata: SnapshotMetadata(appVersion: "1.0.0", collectionDuration: 0.16)
        )
    }

    /// A run of snapshots across a working day, for timeline previews.
    public static var timeline: [Snapshot] {
        [macBaseline, macAfterWorkday, macWithPermissionProblem]
    }
}
