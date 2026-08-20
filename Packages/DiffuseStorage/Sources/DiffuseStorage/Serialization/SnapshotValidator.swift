import DiffuseModels
import Foundation

/// Checks a snapshot for internal consistency.
///
/// Used by `diffuse-dev validate`, by the fixture generator and by the test
/// suite. The rules encode the invariants the rest of the system assumes but
/// cannot enforce through the type system — most importantly that every entity
/// has a schema entry describing it, which is what allows the diff engine and
/// the UI to stay generic.
public enum SnapshotValidator {
    public static func validate(_ snapshot: Snapshot) -> [String] {
        var problems: [String] = []

        if snapshot.schemaVersion > SchemaVersion.current {
            problems
                .append(
                    "Schema version \(snapshot.schemaVersion) is newer than this build supports (\(SchemaVersion.current))."
                )
        }
        if snapshot.id.rawValue.isEmpty {
            problems.append("Snapshot has an empty identifier.")
        }
        if snapshot.capturedAt.timeIntervalSince1970 <= 0 {
            problems.append("Snapshot has no capture date.")
        }

        var seenCapabilities = Set<CapabilityID>()
        for section in snapshot.sections {
            let label = section.capability.rawValue

            if !seenCapabilities.insert(section.capability).inserted {
                problems.append("\(label): appears more than once in the snapshot.")
            }
            if section.schema.capability != section.capability {
                problems.append("\(label): schema declares capability '\(section.schema.capability)'.")
            }
            if section.schema.displayName.isEmpty {
                problems.append("\(label): schema has no display name.")
            }
            if !section.status.hasData, !section.entities.isEmpty {
                problems.append("\(label): status is '\(section.status.rawValue)' but the section still has entities.")
            }

            var seenIdentities = Set<EntityIdentity>()
            for entity in section.allEntities {
                if !seenIdentities.insert(entity.identity).inserted {
                    problems
                        .append(
                            "\(label): duplicate entity identity '\(entity.identity)'. Identities must be unique within a section."
                        )
                }
                if entity.displayName.isEmpty {
                    problems.append("\(label): entity '\(entity.identity)' has no display name.")
                }
                if section.schema.descriptor(for: entity.kind) == nil {
                    problems.append("\(label): entity kind '\(entity.kind)' is not described by the section schema.")
                }

                let described = Set((section.schema.descriptor(for: entity.kind)?.properties ?? []).map(\.key))
                for key in entity.sortedPropertyKeys where !described.contains(key) {
                    problems
                        .append("\(label): property '\(key)' on '\(entity.identity)' is not described by the schema.")
                }
            }

            let describedAttributes = Set(section.schema.attributes.map(\.key))
            for key in section.attributes.keys where !describedAttributes.contains(key) {
                problems.append("\(label): section attribute '\(key)' is not described by the schema.")
            }
        }

        problems.append(contentsOf: validateRoundTrip(snapshot))
        return problems
    }

    /// Encoding then decoding must yield an identical snapshot. This is the
    /// property that makes exports trustworthy and golden fixtures stable.
    static func validateRoundTrip(_ snapshot: Snapshot) -> [String] {
        do {
            let encoded = try SnapshotCoding.encode(snapshot)
            let decoded = try SnapshotCoding.decodeSnapshot(encoded)
            guard decoded == snapshot else {
                return [
                    "Snapshot does not survive a JSON round trip unchanged: \(describeDifference(snapshot, decoded)).",
                ]
            }
            let reencoded = try SnapshotCoding.encode(decoded)
            guard reencoded == encoded else {
                return ["Snapshot encoding is not stable across two encodes."]
            }
            return []
        } catch {
            return ["Snapshot could not be encoded: \(error)"]
        }
    }

    /// Pinpoints the first field that changed across a round trip.
    ///
    /// "Something differs" is not an actionable failure message; the field name
    /// and the two values are.
    static func describeDifference(_ original: Snapshot, _ decoded: Snapshot) -> String {
        if original.capturedAt != decoded.capturedAt {
            return "capturedAt \(original.capturedAt.timeIntervalSinceReferenceDate) → \(decoded.capturedAt.timeIntervalSinceReferenceDate)"
        }
        if original.metadata != decoded.metadata {
            return "metadata"
        }

        let originalSections = original.sections.sorted { $0.capability < $1.capability }
        let decodedSections = decoded.sections.sorted { $0.capability < $1.capability }
        guard originalSections.count == decodedSections.count else {
            return "section count \(originalSections.count) → \(decodedSections.count)"
        }

        for (left, right) in zip(originalSections, decodedSections) where left != right {
            if left.collectedAt != right.collectedAt {
                return "\(left.capability).collectedAt \(left.collectedAt.timeIntervalSinceReferenceDate) → \(right.collectedAt.timeIntervalSinceReferenceDate)"
            }
            if left.duration != right.duration {
                return "\(left.capability).duration \(left.duration) → \(right.duration)"
            }
            if left.schema != right.schema {
                return "\(left.capability).schema"
            }
            if left.diagnostics != right.diagnostics {
                return "\(left.capability).diagnostics"
            }

            for (a, b) in zip(left.sortedEntities, right.sortedEntities) where a != b {
                for key in Set(a.properties.keys).union(b.properties.keys).sorted() where a[key] != b[key] {
                    return "\(left.capability)/\(a.identity)/\(key): \(a[key]) → \(b[key])"
                }
                return "\(left.capability)/\(a.identity)"
            }
            return "\(left.capability)"
        }

        return "unknown field"
    }
}
