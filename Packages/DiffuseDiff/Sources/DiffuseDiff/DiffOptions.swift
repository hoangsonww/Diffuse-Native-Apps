import DiffuseModels
import Foundation

/// Tuning for a diff run.
///
/// Options change *what is reported*, never *how comparison works* — the
/// comparison rules live in each capability's schema. That separation keeps
/// the engine's output reproducible for a given options value.
public struct DiffOptions: Sendable, Hashable {
    /// Changes below this severity are computed but omitted from the result.
    public var minimumSeverity: ChangeSeverity

    /// Emit `.unchanged` changes for entities that compared equal. Off by
    /// default; used by the CLI's `--verbose` mode and by tests.
    public var includeUnchanged: Bool

    /// Report a change when a section's collection status differs between the
    /// two snapshots, e.g. `collected → permissionRequired`.
    public var includeStatusChanges: Bool

    /// Compare nested child entities as first-class entities.
    public var includeChildren: Bool

    /// Maximum gap between two changes for them to land in the same temporal
    /// cluster.
    public var correlationWindow: TimeInterval

    /// Minimum number of changes before a cluster is worth reporting.
    public var minimumClusterSize: Int

    /// Capabilities to exclude entirely.
    public var excludedCapabilities: Set<CapabilityID>

    /// When set, only these capabilities are compared.
    public var includedCapabilities: Set<CapabilityID>?

    public init(
        minimumSeverity: ChangeSeverity = .informational,
        includeUnchanged: Bool = false,
        includeStatusChanges: Bool = true,
        includeChildren: Bool = true,
        correlationWindow: TimeInterval = 300,
        minimumClusterSize: Int = 2,
        excludedCapabilities: Set<CapabilityID> = [],
        includedCapabilities: Set<CapabilityID>? = nil
    ) {
        self.minimumSeverity = minimumSeverity
        self.includeUnchanged = includeUnchanged
        self.includeStatusChanges = includeStatusChanges
        self.includeChildren = includeChildren
        self.correlationWindow = correlationWindow
        self.minimumClusterSize = minimumClusterSize
        self.excludedCapabilities = excludedCapabilities
        self.includedCapabilities = includedCapabilities
    }

    public static let `default` = DiffOptions()

    /// Only the changes a person would call out loud.
    public static let significantOnly = DiffOptions(minimumSeverity: .significant)

    /// Everything, including equalities. Used by fixture generation.
    public static let exhaustive = DiffOptions(includeUnchanged: true, minimumClusterSize: 1)

    func allows(_ capability: CapabilityID) -> Bool {
        if excludedCapabilities.contains(capability) {
            return false
        }
        if let includedCapabilities {
            return includedCapabilities.contains(capability)
        }
        return true
    }
}
