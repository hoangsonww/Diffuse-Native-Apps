import DiffuseCapabilities
import DiffuseModels
import Foundation
import Network

// MARK: - Interfaces

public struct NetworkInterfaceSnapshot: CollectedSection {
    public struct Interface: Sendable {
        public var name: String
        public var displayName: String
        public var isUp: Bool
        public var isLoopback: Bool
        public var ipv4: String?
        public var ipv6: String?

        public init(
            name: String,
            displayName: String,
            isUp: Bool,
            isLoopback: Bool,
            ipv4: String? = nil,
            ipv6: String? = nil
        ) {
            self.name = name
            self.displayName = displayName
            self.isUp = isUp
            self.isLoopback = isLoopback
            self.ipv4 = ipv4
            self.ipv6 = ipv6
        }
    }

    public let interfaces: [Interface]

    public init(interfaces: [Interface]) {
        self.interfaces = interfaces
    }

    public static let schema = SectionSchema(
        capability: "network.interfaces",
        displayName: "Network interfaces",
        summary: "Which network interfaces exist and which are carrying traffic.",
        category: .network,
        symbol: "network",
        privacy: .sensitive,
        entityKinds: [
            EntityKindDescriptor(
                kind: .networkInterface,
                singularName: "Interface",
                pluralName: "Interfaces",
                symbol: "cable.connector",
                summary: "A network interface, identified by its BSD name so it survives address changes.",
                additionSeverity: .significant,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .isActive,
                        displayName: "Active",
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .ipv4Address,
                        displayName: "IPv4 address",
                        summary: "A local address. Redacted from exports by default.",
                        severity: .notable,
                        privacy: .sensitive,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .ipv6Address,
                        displayName: "IPv6 address",
                        severity: .informational,
                        privacy: .sensitive,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .interfaceType,
                        displayName: "Type",
                        severity: .notable,
                        displayOrder: 3
                    ),
                ]
            ),
        ],
        displayOrder: 30
    )

    public var entities: [SnapshotEntity] {
        interfaces.map { interface in
            SnapshotEntity(
                kind: .networkInterface,
                id: interface.name,
                displayName: interface.displayName,
                subtitle: interface.name,
                properties: [
                    .isActive: .boolean(interface.isUp),
                    .ipv4Address: interface.ipv4.map { PropertyValue.identifier($0) } ?? .absent,
                    .ipv6Address: interface.ipv6.map { PropertyValue.identifier($0) } ?? .absent,
                    .interfaceType: .string(Self.describeType(interface.name)),
                ],
                tags: interface.isUp ? ["active"] : []
            )
        }
    }

    /// Maps BSD interface prefixes to something a person recognises.
    public static func describeType(_ name: String) -> String {
        switch true {
        case name.hasPrefix("lo"): "Loopback"
        case name.hasPrefix("en"): "Ethernet or Wi-Fi"
        case name.hasPrefix("awdl"), name.hasPrefix("llw"): "Apple Wireless Direct"
        case name.hasPrefix("utun"), name.hasPrefix("ipsec"), name.hasPrefix("ppp"): "Tunnel or VPN"
        case name.hasPrefix("bridge"): "Bridge"
        case name.hasPrefix("pdp_ip"): "Cellular"
        case name.hasPrefix("anpi"), name.hasPrefix("ap"): "Internal"
        default: "Other"
        }
    }
}

/// Enumerates network interfaces via `getifaddrs`.
///
/// Works identically on every Apple platform and needs no entitlement, which
/// makes it the network baseline all four apps share.
public struct NetworkInterfaceCollector: SnapshotCollector {
    public let identifier: CollectorID = "shared.network.interfaces"
    public let version: SemanticVersion = "1.0.0"

    /// Loopback and Apple's internal link-local interfaces are noise in a diff.
    private let includesLoopback: Bool

    public init(includesLoopback: Bool = false) {
        self.includesLoopback = includesLoopback
    }

    public func collect(context _: CollectionContext) async throws -> NetworkInterfaceSnapshot {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            throw CollectorError.unavailable("Could not enumerate network interfaces")
        }
        defer { freeifaddrs(head) }

        var byName: [String: NetworkInterfaceSnapshot.Interface] = [:]

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isLoopback, !includesLoopback {
                continue
            }

            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            var entry = byName[name] ?? NetworkInterfaceSnapshot.Interface(
                name: name,
                displayName: name,
                isUp: isUp,
                isLoopback: isLoopback
            )
            entry.isUp = entry.isUp || isUp

            if let address = interface.ifa_addr {
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    entry.ipv4 = entry.ipv4 ?? Self.presentation(address)
                case AF_INET6:
                    // Link-local addresses are regenerated constantly and would
                    // produce a change on every snapshot.
                    if let text = Self.presentation(address), !text.hasPrefix("fe80") {
                        entry.ipv6 = entry.ipv6 ?? text
                    }
                default:
                    break
                }
            }

            byName[name] = entry
        }

        let interfaces = byName.values
            .map { interface -> NetworkInterfaceSnapshot.Interface in
                var copy = interface
                copy.displayName = NetworkInterfaceSnapshot.describeType(interface.name) == "Other"
                    ? interface.name
                    : "\(interface.name) · \(NetworkInterfaceSnapshot.describeType(interface.name))"
                return copy
            }
            .sorted { $0.name < $1.name }

        return NetworkInterfaceSnapshot(interfaces: interfaces)
    }

    private static func presentation(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_len)
        guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        let text = String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // Strip the scope suffix (`%en0`) so an address does not appear to
        // change when interface indices are reassigned.
        return text.split(separator: "%").first.map(String.init)
    }
}

public extension NetworkInterfaceCollector {
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                NetworkInterfaceSnapshot.self,
                summary: "Which interfaces are up and what local addresses they hold.",
                collectionDescription: "Lists network interface names, whether each is up, and their local IP "
                    + "addresses. No traffic is inspected and nothing is sent anywhere. Addresses are classified "
                    + "as sensitive and are redacted from exports by default.",
                platforms: platforms,
                cost: .low
            ),
            collector: { NetworkInterfaceCollector() }
        ).erased
    }
}

// MARK: - Path

public struct NetworkPathSnapshot: CollectedSection {
    public struct Path: Sendable {
        public var status: String
        public var primaryInterface: String?
        public var interfaceType: String
        public var isExpensive: Bool
        public var isConstrained: Bool
        public var supportsIPv4: Bool
        public var supportsIPv6: Bool
        public var usesVPN: Bool

        public init(
            status: String,
            primaryInterface: String?,
            interfaceType: String,
            isExpensive: Bool,
            isConstrained: Bool,
            supportsIPv4: Bool,
            supportsIPv6: Bool,
            usesVPN: Bool
        ) {
            self.status = status
            self.primaryInterface = primaryInterface
            self.interfaceType = interfaceType
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
            self.supportsIPv4 = supportsIPv4
            self.supportsIPv6 = supportsIPv6
            self.usesVPN = usesVPN
        }
    }

    public let path: Path

    public init(path: Path) {
        self.path = path
    }

    public static let schema = SectionSchema(
        capability: "network.path",
        displayName: "Connectivity",
        summary: "How this device is currently reaching the network.",
        category: .network,
        symbol: "wifi",
        privacy: .local,
        entityKinds: [
            EntityKindDescriptor(
                kind: .networkPath,
                singularName: "Connection",
                pluralName: "Connections",
                symbol: "wifi",
                summary: "The current default route. Identity is fixed, so switching from Wi-Fi to cellular "
                    + "reads as a property change rather than one connection vanishing and another appearing.",
                additionSeverity: .notable,
                removalSeverity: .significant,
                properties: [
                    PropertyDescriptor(
                        key: .interfaceType,
                        displayName: "Connection",
                        summary: "Wi-Fi, cellular, wired or loopback.",
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 0
                    ),
                    PropertyDescriptor(
                        key: .pathStatus,
                        displayName: "Status",
                        severity: .significant,
                        isPrimary: true,
                        displayOrder: 1
                    ),
                    PropertyDescriptor(
                        key: .usesVPN,
                        displayName: "VPN",
                        summary: "Whether the default route runs through a tunnel interface.",
                        severity: .significant,
                        displayOrder: 2
                    ),
                    PropertyDescriptor(
                        key: .isExpensive,
                        displayName: "Metered",
                        severity: .notable,
                        displayOrder: 3
                    ),
                    PropertyDescriptor(
                        key: .isConstrained,
                        displayName: "Low Data Mode",
                        severity: .notable,
                        displayOrder: 4
                    ),
                    PropertyDescriptor(
                        key: .interfaceName,
                        displayName: "Interface",
                        severity: .notable,
                        displayOrder: 5
                    ),
                ]
            ),
        ],
        displayOrder: 31
    )

    public var entities: [SnapshotEntity] {
        [
            SnapshotEntity(
                kind: .networkPath,
                id: "default",
                displayName: path.interfaceType,
                subtitle: path.status,
                properties: [
                    .interfaceType: .string(path.interfaceType),
                    .pathStatus: .string(path.status),
                    .usesVPN: .boolean(path.usesVPN),
                    .isExpensive: .boolean(path.isExpensive),
                    .isConstrained: .boolean(path.isConstrained),
                    .interfaceName: path.primaryInterface.map { PropertyValue.string($0) } ?? .absent,
                ],
                tags: path.usesVPN ? ["vpn"] : []
            ),
        ]
    }
}

/// Reads the current default network path via `NWPathMonitor`.
///
/// `NWPathMonitor` is push-based, so the collector waits for the first update
/// and then cancels rather than leaving a monitor running for the app's
/// lifetime.
public struct NetworkPathCollector: SnapshotCollector {
    public let identifier: CollectorID = "shared.network.path"
    public let version: SemanticVersion = "1.0.0"

    public init() {}

    public func collect(context _: CollectionContext) async throws -> NetworkPathSnapshot {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.diffuse.network-path")

        let path: NWPath? = await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)
            monitor.pathUpdateHandler = { path in
                box.resume(with: path)
            }
            monitor.start(queue: queue)

            // A path update normally arrives within milliseconds. The fallback
            // keeps the collector from waiting for its whole deadline on a
            // device with no interfaces at all.
            queue.asyncAfter(deadline: .now() + 1.5) {
                box.resume(with: monitor.currentPath)
            }
        }
        monitor.cancel()

        guard let path else {
            throw CollectorError.temporarilyUnavailable
        }

        let primary = path.availableInterfaces.first
        return NetworkPathSnapshot(
            path: .init(
                status: Self.describe(path.status),
                primaryInterface: primary?.name,
                interfaceType: primary.map { Self.describe($0.type) } ?? "None",
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained,
                supportsIPv4: path.supportsIPv4,
                supportsIPv6: path.supportsIPv6,
                usesVPN: Self.usesVPN(primaryName: primary?.name, primaryType: primary?.type)
            )
        )
    }

    static func describe(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied: "Connected"
        case .unsatisfied: "Disconnected"
        case .requiresConnection: "Requires connection"
        @unknown default: "Unknown"
        }
    }

    static func describe(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wiredEthernet: "Wired Ethernet"
        case .loopback: "Loopback"
        case .other: "Other"
        @unknown default: "Unknown"
        }
    }

    /// macOS always has idle `utun` interfaces, so "any utun exists" is not a
    /// VPN. The path's primary interface is, once the tunnel is actually in use.
    static func usesVPN(primaryName: String?, primaryType: NWInterface.InterfaceType?) -> Bool {
        let name = (primaryName ?? "").lowercased()
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") {
            return true
        }
        return primaryType == .other && (name.contains("vpn") || name.contains("ipsec"))
    }
}

/// Guards a `CheckedContinuation` against the double-resume that a push-based
/// API plus a timeout fallback would otherwise cause.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NWPath?, Never>?

    init(_ continuation: CheckedContinuation<NWPath?, Never>) {
        self.continuation = continuation
    }

    func resume(with path: NWPath?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: path)
    }
}

extension CollectorError {
    static var temporarilyUnavailable: CollectorError {
        .unavailable("No network path is available right now")
    }
}

public extension NetworkPathCollector {
    static func capability(platforms: Set<Platform>) -> AnyCapability {
        BasicCapability(
            metadata: .describing(
                NetworkPathSnapshot.self,
                summary: "Wi-Fi versus cellular, VPN, and whether the link is metered.",
                collectionDescription: "Reads the current default network route: its type (Wi-Fi, cellular, "
                    + "wired), whether it is satisfied, whether a VPN tunnel is in use, and whether the system "
                    + "considers it expensive or constrained. No traffic is inspected.",
                platforms: platforms,
                cost: .low
            ),
            collector: { NetworkPathCollector() }
        ).erased
    }
}
