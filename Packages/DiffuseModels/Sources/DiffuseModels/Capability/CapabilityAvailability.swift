import Foundation

/// Why a capability can or cannot produce data right now.
///
/// The application never asks *why* Docker is missing — it receives one of
/// these and renders it generically. That is what keeps "add Rust support"
/// from touching the UI.
public enum CapabilityAvailability: Sendable, Hashable, Codable {
    /// Ready to collect.
    case available

    /// The underlying thing simply is not present, e.g. Docker is not installed.
    /// The UI hides these rather than showing a wall of "not supported".
    case unavailable(reason: String)

    /// This platform can never support the capability, e.g. process inspection
    /// on watchOS.
    case unsupported(reason: String)

    /// A user-grantable permission is missing.
    case permissionRequired(PermissionRequirement)

    /// Present, but not answering right now — a daemon is down, a device is
    /// asleep. Worth retrying on the next snapshot.
    case temporarilyUnavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    /// Whether the capability should appear in the capability list at all.
    /// Unsupported capabilities are noise on platforms that can never have them.
    public var isDiscoverable: Bool {
        if case .unsupported = self {
            return false
        }
        return true
    }

    /// Whether a later snapshot might succeed without user action.
    public var isRetryable: Bool {
        switch self {
        case .available, .temporarilyUnavailable, .unavailable: true
        case .unsupported, .permissionRequired: false
        }
    }

    public var displayName: String {
        switch self {
        case .available: "Available"
        case .unavailable: "Not detected"
        case .unsupported: "Not supported"
        case .permissionRequired: "Permission required"
        case .temporarilyUnavailable: "Temporarily unavailable"
        }
    }

    public var detail: String? {
        switch self {
        case .available: nil
        case let .unavailable(reason), let .unsupported(reason), let .temporarilyUnavailable(reason): reason
        case let .permissionRequired(requirement): requirement.rationale
        }
    }

    public var symbol: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .unavailable: "circle.dashed"
        case .unsupported: "minus.circle"
        case .permissionRequired: "lock.circle.fill"
        case .temporarilyUnavailable: "clock.badge.exclamationmark"
        }
    }

    /// The collection status a section should carry if a snapshot is taken
    /// while the capability is in this state.
    public var collectionStatus: CollectionStatus {
        switch self {
        case .available: .collected
        case .unavailable: .unavailable
        case .unsupported: .unsupported
        case .permissionRequired: .permissionRequired
        case .temporarilyUnavailable: .unavailable
        }
    }
}

// MARK: - Codable

public extension CapabilityAvailability {
    private enum CodingKeys: String, CodingKey {
        case state, reason, permission
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        switch state {
        case "available":
            self = .available
        case "unavailable":
            self = try .unavailable(reason: container.decode(String.self, forKey: .reason))
        case "unsupported":
            self = try .unsupported(reason: container.decode(String.self, forKey: .reason))
        case "permissionRequired":
            self = try .permissionRequired(container.decode(PermissionRequirement.self, forKey: .permission))
        case "temporarilyUnavailable":
            self = try .temporarilyUnavailable(reason: container.decode(String.self, forKey: .reason))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Unknown availability state '\(state)'"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available:
            try container.encode("available", forKey: .state)
        case let .unavailable(reason):
            try container.encode("unavailable", forKey: .state)
            try container.encode(reason, forKey: .reason)
        case let .unsupported(reason):
            try container.encode("unsupported", forKey: .state)
            try container.encode(reason, forKey: .reason)
        case let .permissionRequired(requirement):
            try container.encode("permissionRequired", forKey: .state)
            try container.encode(requirement, forKey: .permission)
        case let .temporarilyUnavailable(reason):
            try container.encode("temporarilyUnavailable", forKey: .state)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// A capability plus its current availability, as presented in the
/// Capabilities screen.
public struct CapabilityStatus: Sendable, Hashable, Codable, Identifiable {
    public let metadata: CapabilityMetadata
    public var availability: CapabilityAvailability

    /// Whether the user has this capability switched on.
    public var isEnabled: Bool

    public var id: CapabilityID {
        metadata.id
    }

    public init(metadata: CapabilityMetadata, availability: CapabilityAvailability, isEnabled: Bool = true) {
        self.metadata = metadata
        self.availability = availability
        self.isEnabled = isEnabled
    }

    /// Whether this capability will contribute to the next snapshot.
    public var willCollect: Bool {
        isEnabled && availability.isAvailable
    }
}
