#if os(macOS)

import DiffuseCapabilities
import DiffuseModels
import Foundation

public struct MacApplicationsSnapshot: CollectedSection {
    public struct Application: Sendable {
        public var bundleIdentifier: String
        public var name: String
        public var version: String
        public var buildNumber: String?
        public var path: String

        public init(
            bundleIdentifier: String,
            name: String,
            version: String,
            buildNumber: String?,
            path: String
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.version = version
            self.buildNumber = buildNumber
            self.path = path
        }
    }

    public let applications: [Application]
    public let diagnostics: [Diagnostic]

    public init(applications: [Application], diagnostics: [Diagnostic] = []) {
        self.applications = applications
        self.diagnostics = diagnostics
    }

    public static let schema = SectionSchema(
        capability: "software.applications",
        displayName: "Applications",
        summary: "Installed applications and their versions.",
        category: .software,
        symbol: "app.badge",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .application,
                singularName: "Application",
                pluralName: "Applications",
                symbol: "app",
                summary: "Identified by bundle identifier, so renaming an app does not read as an "
                    + "uninstall followed by an install.",
                additionSeverity: .notable,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .version,
                        displayName: "Version",
                        unit: .version,
                        severity: .notable,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .buildNumber,
                        displayName: "Build",
                        severity: .informational,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .bundleIdentifier,
                        displayName: "Bundle identifier",
                        severity: .significant,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .installPath,
                        displayName: "Location",
                        unit: .path,
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 3
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: "applicationCount",
                displayName: "Applications installed",
                unit: .count,
                comparison: .exact,
                severity: .notable
            ),
        ],
        displayOrder: 50
    )

    public var attributes: [PropertyKey: PropertyValue] {
        ["applicationCount": .integer(Int64(applications.count))]
    }

    public var entities: [SnapshotEntity] {
        applications.map { application in
            SnapshotEntity(
                kind: .application,
                id: application.bundleIdentifier,
                displayName: application.name,
                subtitle: application.version,
                properties: [
                    .version: SemanticVersion(application.version).map { PropertyValue.version($0) }
                        ?? .string(application.version),
                    .buildNumber: application.buildNumber.map { PropertyValue.string($0) } ?? .absent,
                    .bundleIdentifier: .identifier(application.bundleIdentifier),
                    .installPath: .path(application.path),
                ]
            )
        }
    }
}

/// Enumerates installed applications by reading `Info.plist` bundles.
///
/// Only the app directories are scanned, and only the property list is
/// read — never application data, preferences or documents.
public struct MacApplicationsCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.software.applications"
    public let version: SemanticVersion = "1.0.0"

    public static let defaultSearchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    private let searchPaths: [String]
    private let fileSystem: any FileSystemProviding

    public init(
        searchPaths: [String] = MacApplicationsCollector.defaultSearchPaths,
        fileSystem: any FileSystemProviding = SystemFileSystem()
    ) {
        self.searchPaths = searchPaths
        self.fileSystem = fileSystem
    }

    public func collect(context _: CollectionContext) async throws -> MacApplicationsSnapshot {
        var applications: [String: MacApplicationsSnapshot.Application] = [:]
        var diagnostics: [Diagnostic] = []

        for directory in searchPaths {
            guard fileSystem.isDirectory(at: directory) else { continue }
            let entries: [String]
            do {
                entries = try fileSystem.contentsOfDirectory(at: directory)
            } catch {
                diagnostics.append(.warning("Could not list \(directory)", detail: error.localizedDescription))
                continue
            }

            for entry in entries where entry.hasSuffix(".app") {
                let bundlePath = (directory as NSString).appendingPathComponent(entry)
                guard let application = readBundle(at: bundlePath) else { continue }
                // Earlier search paths win, matching the order macOS itself
                // resolves duplicate installs in.
                if applications[application.bundleIdentifier] == nil {
                    applications[application.bundleIdentifier] = application
                }
            }
        }

        return MacApplicationsSnapshot(
            applications: applications.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier },
            diagnostics: diagnostics
        )
    }

    private func readBundle(at path: String) -> MacApplicationsSnapshot.Application? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? fileSystem.readFile(at: plistPath, maximumBytes: 512 * 1024),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        else { return nil }

        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension

        return MacApplicationsSnapshot.Application(
            bundleIdentifier: bundleIdentifier,
            name: name,
            version: (plist["CFBundleShortVersionString"] as? String) ?? "0",
            buildNumber: plist["CFBundleVersion"] as? String,
            path: path
        )
    }
}

public extension MacApplicationsCollector {
    static var capability: AnyCapability {
        BasicCapability(
            metadata: .describing(
                MacApplicationsSnapshot.self,
                summary: "Which apps are installed and at what version.",
                collectionDescription: "Lists .app bundles in the standard application directories and reads "
                    + "each bundle's Info.plist for its name, identifier and version. Application data, "
                    + "preferences and documents are never read.",
                platforms: [.macOS],
                cost: .moderate
            ),
            collector: { MacApplicationsCollector() }
        ).erased
    }
}

#endif
