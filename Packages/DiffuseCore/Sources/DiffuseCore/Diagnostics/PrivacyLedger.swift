import DiffuseCapabilities
import DiffuseModels
import Foundation

/// The complete, generated answer to "what does Diffuse collect?".
///
/// Built from live capability metadata rather than maintained by hand, so the
/// privacy screen cannot drift out of date when a collector is added. A
/// hand-written privacy page is a promise; a generated one is a fact.
public struct PrivacyLedger: Sendable {
    public struct Entry: Sendable, Identifiable {
        public let capability: CapabilityID
        public let displayName: String
        public let category: SectionCategory
        public let symbol: String
        public let privacy: PrivacyClassification
        public let collectionDescription: String
        public let permissions: [PermissionRequirement]
        public let availability: CapabilityAvailability
        public let isEnabled: Bool

        /// The properties this capability records, with their own
        /// classifications, so the user can see the detail rather than a
        /// reassuring summary.
        public let properties: [PropertyDescriptor]

        public var id: CapabilityID {
            capability
        }
    }

    public let entries: [Entry]

    /// Things Diffuse never reads, stated explicitly. Not derived — this is a
    /// design commitment, and it is asserted by the test suite.
    public static let neverCollected: [String] = [
        "Passwords, tokens or API keys",
        "Keychain contents",
        "SSH or GPG private keys",
        "Environment variable values, including .env files",
        "File contents of any kind",
        "Message, mail, photo or browsing history",
        "Location data",
        "Anything at all sent off the device",
    ]

    public init(statuses: [CapabilityStatus]) {
        entries = statuses
            .map { status in
                Entry(
                    capability: status.metadata.id,
                    displayName: status.metadata.displayName,
                    category: status.metadata.category,
                    symbol: status.metadata.symbol,
                    privacy: status.metadata.privacy,
                    collectionDescription: status.metadata.collectionDescription,
                    permissions: status.metadata.permissions,
                    availability: status.availability,
                    isEnabled: status.isEnabled,
                    properties: status.metadata.schema.entityKinds
                        .flatMap(\.orderedProperties)
                        + status.metadata.schema.attributes
                )
            }
            .sorted {
                if $0.privacy != $1.privacy {
                    return $0.privacy > $1.privacy
                }
                if $0.category != $1.category {
                    return $0.category < $1.category
                }
                return $0.displayName < $1.displayName
            }
    }

    public var groupedByClassification: [(classification: PrivacyClassification, entries: [Entry])] {
        Dictionary(grouping: entries, by: \.privacy)
            .map { (classification: $0.key, entries: $0.value) }
            .sorted { $0.classification > $1.classification }
    }

    /// Capabilities that would have values redacted under a policy, so the
    /// export sheet can say what the user is about to leave out.
    public func redactedCapabilities(under policy: RedactionPolicy) -> [Entry] {
        entries.filter { entry in
            policy.redacts(entry.privacy)
                || entry.properties.contains { policy.redacts($0.privacy) }
        }
    }

    public func markdown() -> String {
        var lines = ["# What Diffuse collects", ""]
        lines.append("Diffuse stores everything locally. Nothing is uploaded, and there is no account.")
        lines.append("")
        lines.append("## Never collected")
        lines.append("")
        for item in Self.neverCollected {
            lines.append("- \(item)")
        }
        lines.append("")

        for group in groupedByClassification {
            lines.append("## \(group.classification.displayName)")
            lines.append("")
            lines.append("_\(group.classification.summary)_")
            lines.append("")
            for entry in group.entries {
                lines.append("### \(entry.displayName)")
                lines.append("")
                lines.append(entry.collectionDescription)
                lines.append("")
                if !entry.permissions.isEmpty {
                    lines.append("Requires: " + entry.permissions.map(\.displayName).joined(separator: ", "))
                    lines.append("")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
