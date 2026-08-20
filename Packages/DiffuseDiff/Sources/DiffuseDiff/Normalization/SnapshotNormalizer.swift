import DiffuseModels
import Foundation

/// Puts a section into canonical form before comparison.
///
/// Two collector runs can legitimately produce the same state in a different
/// order, with duplicate entries, or with a property present in one run and
/// absent in the other. Normalizing first is what makes `diff(A, A)` empty and
/// makes entity ordering irrelevant to the result.
public enum SnapshotNormalizer {
    /// A section flattened into a deterministic, identity-keyed form.
    public struct NormalizedSection: Sendable {
        public let capability: CapabilityID
        public let schema: SectionSchema
        public let status: CollectionStatus
        public let collectedAt: Date
        public let attributes: [PropertyKey: PropertyValue]

        /// Every entity in the section, including descendants, keyed by
        /// identity. Duplicates collapse onto the first occurrence.
        public let entities: [EntityIdentity: SnapshotEntity]

        /// Identities in stable sorted order.
        public let order: [EntityIdentity]

        /// Duplicate identities encountered while flattening. Surfaced as a
        /// diagnostic rather than silently discarded, because a collector
        /// emitting duplicate identities is a bug worth seeing.
        public let duplicateIdentities: [EntityIdentity]
    }

    public static func normalize(_ section: SnapshotSection, includeChildren: Bool) -> NormalizedSection {
        var entities: [EntityIdentity: SnapshotEntity] = [:]
        var duplicates: [EntityIdentity] = []

        let candidates = includeChildren ? section.entities.flatMap(\.flattened) : section.entities
        for entity in candidates {
            let normalized = normalize(entity, includeChildren: includeChildren)
            if entities[normalized.identity] != nil {
                duplicates.append(normalized.identity)
                continue
            }
            entities[normalized.identity] = normalized
        }

        return NormalizedSection(
            capability: section.capability,
            schema: section.schema,
            status: section.status,
            collectedAt: section.collectedAt,
            attributes: normalizeAttributes(section.attributes),
            entities: entities,
            order: entities.keys.sorted(),
            duplicateIdentities: duplicates.sorted()
        )
    }

    /// Strips a single entity down to comparable form: children are handled
    /// separately by the flattening pass, and explicitly-absent properties are
    /// dropped so "absent" and "not reported" compare identically.
    static func normalize(_ entity: SnapshotEntity, includeChildren: Bool) -> SnapshotEntity {
        var copy = entity
        copy.properties = entity.properties.filter { !$0.value.isAbsent }
        copy.children = includeChildren ? [] : entity.children
        return copy
    }

    static func normalizeAttributes(_ attributes: [PropertyKey: PropertyValue]) -> [PropertyKey: PropertyValue] {
        attributes.filter { !$0.value.isAbsent }
    }
}
