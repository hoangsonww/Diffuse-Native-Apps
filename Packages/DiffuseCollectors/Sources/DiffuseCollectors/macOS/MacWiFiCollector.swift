#if os(macOS)

import CoreLocation
import CoreWLAN
import DiffuseCapabilities
import DiffuseModels
import Foundation

public struct MacWiFiSnapshot: CollectedSection {
    public struct Network: Sendable {
        public var interfaceName: String
        public var ssid: String?
        public var bssidAvailable: Bool
        public var rssi: Int
        public var noise: Int
        public var channel: Int?
        public var channelBand: String?
        public var security: String
        public var transmitRate: Double

        public init(
            interfaceName: String,
            ssid: String?,
            bssidAvailable: Bool,
            rssi: Int,
            noise: Int,
            channel: Int?,
            channelBand: String?,
            security: String,
            transmitRate: Double
        ) {
            self.interfaceName = interfaceName
            self.ssid = ssid
            self.bssidAvailable = bssidAvailable
            self.rssi = rssi
            self.noise = noise
            self.channel = channel
            self.channelBand = channelBand
            self.security = security
            self.transmitRate = transmitRate
        }
    }

    public let network: Network?
    public let diagnostics: [Diagnostic]
    public let locationAccessGranted: Bool

    public init(network: Network?, diagnostics: [Diagnostic] = [], locationAccessGranted: Bool = true) {
        self.network = network
        self.diagnostics = diagnostics
        self.locationAccessGranted = locationAccessGranted
    }

    public static let schema = SectionSchema(
        capability: "network.wifi",
        displayName: "Wi-Fi",
        summary: "Which wireless network this Mac is joined to.",
        category: .network,
        symbol: "wifi",
        privacy: .sensitive,
        entityKinds: [
            EntityKindDescriptor(
                kind: .wifiNetwork,
                singularName: "Wi-Fi connection",
                pluralName: "Wi-Fi connections",
                symbol: "wifi",
                summary: "Identity is the interface, not the network name. Moving from one network to "
                    + "another is therefore a property change — 'Home → Office' — rather than one network "
                    + "disappearing and another appearing.",
                additionSeverity: .notable,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .ssid,
                        displayName: "Network",
                        summary: "The network name identifies where you are, so it is treated as sensitive "
                            + "and redacted from exports by default.",
                        severity: .significant,
                        privacy: .sensitive,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .security,
                        displayName: "Security",
                        severity: .significant,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .signalStrength,
                        displayName: "Signal",
                        summary: "Signal strength fluctuates constantly; only a swing of more than 10 dBm is reported.",
                        comparison: .numeric(tolerance: 10),
                        severity: .informational,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .channel,
                        displayName: "Channel",
                        unit: .count,
                        severity: .informational,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(key: "channelBand", displayName: "Band", severity: .notable, displayOrder: 4),
                    PropertyDescriptor(
                        key: "transmitRate",
                        displayName: "Transmit rate",
                        comparison: .relative(tolerance: 0.3),
                        severity: .informational,
                        displayOrder: 5
                    ),
                ]
            ),
        ],
        displayOrder: 32
    )

    public var status: CollectionStatus {
        guard let network else { return .unavailable }
        if network.ssid != nil {
            return .collected
        }
        // A nil SSID means either "not joined" or "Location Services denied".
        return locationAccessGranted ? .unavailable : .permissionRequired
    }

    public var entities: [SnapshotEntity] {
        guard let network, let ssid = network.ssid else { return [] }
        return [
            SnapshotEntity(
                kind: .wifiNetwork,
                id: network.interfaceName,
                displayName: ssid,
                subtitle: network.interfaceName,
                properties: [
                    .ssid: .string(ssid),
                    .security: .string(network.security),
                    .signalStrength: .integer(Int64(network.rssi)),
                    .channel: network.channel.map { PropertyValue.integer(Int64($0)) } ?? .absent,
                    "channelBand": network.channelBand.map { PropertyValue.string($0) } ?? .absent,
                    "transmitRate": .double(network.transmitRate),
                ],
                tags: ["wifi"]
            ),
        ]
    }
}

/// Reads the joined Wi-Fi network via CoreWLAN.
///
/// macOS gates the SSID behind Location Services. Rather than reporting an
/// empty section, the collector distinguishes "no Wi-Fi hardware" from
/// "permission not granted" so the UI can offer the right next step.
public struct MacWiFiCollector: SnapshotCollector {
    public let identifier: CollectorID = "macos.network.wifi"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    public func collect(context _: CollectionContext) async throws -> MacWiFiSnapshot {
        guard let interface = CWWiFiClient.shared().interface() else {
            return MacWiFiSnapshot(network: nil, diagnostics: [.info("No Wi-Fi interface on this Mac")])
        }

        let ssid = interface.ssid()
        let locationAccessGranted = Self.isLocationAuthorized
        let network = MacWiFiSnapshot.Network(
            interfaceName: interface.interfaceName ?? "wifi",
            ssid: ssid,
            bssidAvailable: interface.bssid() != nil,
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            channel: interface.wlanChannel()?.channelNumber,
            channelBand: interface.wlanChannel().map(Self.describe),
            security: Self.describe(interface.security()),
            transmitRate: interface.transmitRate()
        )

        let diagnostics: [Diagnostic] = if ssid != nil {
            []
        } else if locationAccessGranted {
            [.info("Not joined to a Wi-Fi network")]
        } else {
            [
                .warning(
                    "Wi-Fi network name requires Location Services",
                    detail: "macOS only reveals the current SSID to apps with location access. Grant it in "
                        + "System Settings › Privacy & Security › Location Services."
                ),
            ]
        }

        return MacWiFiSnapshot(
            network: network,
            diagnostics: diagnostics,
            locationAccessGranted: locationAccessGranted
        )
    }

    static var isLocationAuthorized: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    static func describe(_ channel: CWChannel) -> String {
        switch channel.channelBand {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        case .bandUnknown: "Unknown"
        @unknown default: "Unknown"
        }
    }

    static func describe(_ security: CWSecurity) -> String {
        switch security {
        case .none: "Open"
        case .WEP: "WEP"
        case .wpaPersonal, .wpaPersonalMixed: "WPA Personal"
        case .wpa2Personal: "WPA2 Personal"
        case .wpa3Personal: "WPA3 Personal"
        case .wpa3Transition: "WPA3 Transition"
        case .personal: "Personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: "WPA Enterprise"
        case .wpa2Enterprise: "WPA2 Enterprise"
        case .wpa3Enterprise: "WPA3 Enterprise"
        case .enterprise: "Enterprise"
        case .dynamicWEP: "Dynamic WEP"
        case .OWE: "OWE"
        case .oweTransition: "OWE Transition"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }
}

public extension MacWiFiCollector {
    static let locationPermission = PermissionRequirement(
        id: "location.wifi",
        displayName: "Location Services",
        rationale: "macOS only reveals the name of the Wi-Fi network you are joined to when an app has "
            + "location access. Diffuse uses it solely to record which network you were on, and never "
            + "reads your coordinates.",
        isRequired: false,
        settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    )

    static var capability: AnyCapability {
        BasicCapability(
            metadata: .describing(
                MacWiFiSnapshot.self,
                summary: "The wireless network you are joined to.",
                collectionDescription: "Reads the name, security type, channel and signal strength of the "
                    + "Wi-Fi network this Mac is joined to. The network name is treated as sensitive and is "
                    + "redacted from exports by default. No passwords are read.",
                platforms: [.macOS],
                permissions: [locationPermission],
                cost: .low,
                privacy: .sensitive
            ),
            availability: {
                guard let interface = CWWiFiClient.shared().interface() else {
                    return .unavailable(reason: "No Wi-Fi hardware")
                }
                guard interface.powerOn() else {
                    return .temporarilyUnavailable(reason: "Wi-Fi is turned off")
                }
                if interface.ssid() != nil || isLocationAuthorized {
                    return .available
                }
                return .permissionRequired(locationPermission)
            },
            collector: { MacWiFiCollector() }
        ).erased
    }
}

#endif
