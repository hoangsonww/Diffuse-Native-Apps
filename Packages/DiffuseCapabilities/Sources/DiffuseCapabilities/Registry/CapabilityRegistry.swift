import DiffuseModels
import Foundation

/// The set of capabilities a platform offers.
///
/// Each app owns exactly one registry. This is the only place where a platform
/// commits to a list of capabilities at compile time — and adding to that list
/// is a one-line change.
public protocol CapabilityRegistry: Sendable {
    var platform: Platform { get }
    var capabilities: [AnyCapability] { get }
}

public extension CapabilityRegistry {
    func capability(with id: CapabilityID) -> AnyCapability? {
        capabilities.first { $0.id == id }
    }

    var capabilityIDs: [CapabilityID] {
        capabilities.map(\.id).sorted()
    }

    /// Capabilities grouped by category, in presentation order.
    var groupedByCategory: [(category: SectionCategory, capabilities: [AnyCapability])] {
        Dictionary(grouping: capabilities, by: \.metadata.category)
            .map { (
                category: $0.key,
                capabilities: $0.value.sorted { $0.metadata.displayName < $1.metadata.displayName }
            ) }
            .sorted { $0.category < $1.category }
    }
}

/// A registry built from a fixed list. Platform registries are thin wrappers
/// around this.
public struct StaticCapabilityRegistry: CapabilityRegistry {
    public let platform: Platform
    public let capabilities: [AnyCapability]

    public init(platform: Platform, capabilities: [AnyCapability]) {
        self.platform = platform
        // Registration order should never influence output. Sorting here means
        // two builds that register in a different order still agree.
        self.capabilities = capabilities.sorted { $0.id < $1.id }
    }

    /// Combines registries, e.g. shared capabilities plus platform-specific
    /// ones. Later entries win on conflict.
    public static func combining(platform: Platform,
                                 _ registries: [any CapabilityRegistry]) -> StaticCapabilityRegistry {
        var merged: [CapabilityID: AnyCapability] = [:]
        for registry in registries {
            for capability in registry.capabilities {
                merged[capability.id] = capability
            }
        }
        return StaticCapabilityRegistry(platform: platform, capabilities: Array(merged.values))
    }
}
