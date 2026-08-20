import DiffuseModels
import Foundation

/// Pairs entities across two snapshots by semantic identity.
///
/// Matching is exact and identity-based on purpose. Heuristic matching (say,
/// "these two displays have similar names, probably the same one") would make
/// results non-deterministic and would quietly hide collector bugs where an
/// identity is unstable. If a collector cannot produce a stable identity, that
/// is a collector problem, not something the diff engine should paper over.
public enum EntityMatcher {
    public struct Result: Sendable {
        /// Identities present only in the later snapshot.
        public let added: [EntityIdentity]

        /// Identities present only in the earlier snapshot.
        public let removed: [EntityIdentity]

        /// Identities present in both, worth comparing property by property.
        public let common: [EntityIdentity]
    }

    public static func match(
        base: SnapshotNormalizer.NormalizedSection,
        target: SnapshotNormalizer.NormalizedSection
    ) -> Result {
        let baseIdentities = Set(base.entities.keys)
        let targetIdentities = Set(target.entities.keys)

        return Result(
            added: targetIdentities.subtracting(baseIdentities).sorted(),
            removed: baseIdentities.subtracting(targetIdentities).sorted(),
            common: baseIdentities.intersection(targetIdentities).sorted()
        )
    }
}
