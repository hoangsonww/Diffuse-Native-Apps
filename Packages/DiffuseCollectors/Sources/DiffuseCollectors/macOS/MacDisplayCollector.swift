#if os(macOS)

import CoreGraphics
import DiffuseCapabilities
import DiffuseModels
import Foundation

public struct MacDisplaySnapshot: CollectedSection {
    public struct Display: Sendable {
        public var identifier: String
        public var name: String
        public var width: Int
        public var height: Int
        public var refreshRate: Double
        public var isMain: Bool
        public var isBuiltIn: Bool
        public var scaleFactor: Double

        public init(
            identifier: String,
            name: String,
            width: Int,
            height: Int,
            refreshRate: Double,
            isMain: Bool,
            isBuiltIn: Bool,
            scaleFactor: Double
        ) {
            self.identifier = identifier
            self.name = name
            self.width = width
            self.height = height
            self.refreshRate = refreshRate
            self.isMain = isMain
            self.isBuiltIn = isBuiltIn
            self.scaleFactor = scaleFactor
        }
    }

    public let displays: [Display]

    public init(displays: [Display]) {
        self.displays = displays
    }

    public static let schema = SectionSchema(
        capability: "display.configuration",
        displayName: "Displays",
        summary: "Connected displays, their resolutions and refresh rates.",
        category: .display,
        symbol: "display",
        privacy: .public,
        entityKinds: [
            EntityKindDescriptor(
                kind: .display,
                singularName: "Display",
                pluralName: "Displays",
                symbol: "display",
                summary: "Identified by its hardware display ID, so changing a resolution reads as a "
                    + "modification rather than one display being swapped for another.",
                additionSeverity: .significant,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .resolution,
                        displayName: "Resolution",
                        unit: .pixels,
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .refreshRate,
                        displayName: "Refresh rate",
                        unit: .hertz,
                        comparison: .numeric(tolerance: 0.5),
                        severity: .notable,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .scaleFactor,
                        displayName: "Scale",
                        comparison: .numeric(tolerance: 0.01),
                        severity: .notable,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(key: .isMain, displayName: "Main display", severity: .notable, displayOrder: 3),
                    PropertyDescriptor(
                        key: .isBuiltIn,
                        displayName: "Built in",
                        severity: .informational,
                        displayOrder: 4
                    ),
                ]
            ),
        ],
        attributes: [
            PropertyDescriptor(
                key: "displayCount",
                displayName: "Displays connected",
                unit: .count,
                severity: .significant
            ),
        ],
        displayOrder: 20
    )

    public var attributes: [PropertyKey: PropertyValue] {
        ["displayCount": .integer(Int64(displays.count))]
    }

    public var entities: [SnapshotEntity] {
        displays.map { display in
            SnapshotEntity(
                kind: .display,
                id: display.identifier,
                displayName: display.name,
                subtitle: "\(display.width) × \(display.height)",
                properties: [
                    .resolution: .string("\(display.width) × \(display.height)"),
                    .refreshRate: .double(display.refreshRate),
                    .scaleFactor: .double(display.scaleFactor),
                    .isMain: .boolean(display.isMain),
                    .isBuiltIn: .boolean(display.isBuiltIn),
                ],
                tags: display.isBuiltIn ? ["built-in"] : ["external"]
            )
        }
    }
}

/// Reads the active display list from Core Graphics.
public struct MacDisplayCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.display.configuration"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    public func collect(context _: CollectionContext) async throws -> MacDisplaySnapshot {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return MacDisplaySnapshot(displays: [])
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            throw CollectorError.unavailable("Could not read the active display list")
        }

        let displays = ids.prefix(Int(count)).filter { $0 != 0 }.map { id -> MacDisplaySnapshot.Display in
            let mode = CGDisplayCopyDisplayMode(id)
            let pixelWidth = mode?.pixelWidth ?? CGDisplayPixelsWide(id)
            let pointWidth = mode?.width ?? CGDisplayPixelsWide(id)
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0

            return MacDisplaySnapshot.Display(
                // The vendor/model/serial triple survives a reboot and a
                // cable swap, unlike the ephemeral CGDirectDisplayID.
                identifier: "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))",
                name: isBuiltIn ? "Built-in Display" : "Display \(CGDisplayModelNumber(id))",
                width: mode?.width ?? CGDisplayPixelsWide(id),
                height: mode?.height ?? CGDisplayPixelsHigh(id),
                refreshRate: mode?.refreshRate ?? 60,
                isMain: CGDisplayIsMain(id) != 0,
                isBuiltIn: isBuiltIn,
                scaleFactor: pointWidth > 0 ? Double(pixelWidth) / Double(pointWidth) : 1
            )
        }

        return MacDisplaySnapshot(displays: displays.sorted { $0.identifier < $1.identifier })
    }
}

public extension MacDisplayCollector {
    static var capability: AnyCapability {
        BasicCapability(
            metadata: .describing(
                MacDisplaySnapshot.self,
                summary: "Which displays are connected and how they are configured.",
                collectionDescription: "Reads the list of active displays and each one's resolution, refresh "
                    + "rate, scale factor and whether it is built in. Nothing on screen is captured.",
                platforms: [.macOS],
                cost: .low
            ),
            collector: { MacDisplayCollector() }
        ).erased
    }
}

#endif
