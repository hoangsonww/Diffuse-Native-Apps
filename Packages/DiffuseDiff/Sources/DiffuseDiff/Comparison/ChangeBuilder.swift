import DiffuseModels
import Foundation

/// Builds the human-readable half of a `Change`.
///
/// Phrasing is derived from schema metadata rather than from the capability, so
/// a brand new collector produces sentences that read as well as the built-in
/// ones without writing any presentation code.
enum ChangeBuilder {
    /// The synthetic property key used to report a display-name change on an
    /// entity whose identity stayed stable.
    static let displayNameKey = PropertyKey("__displayName")

    /// The synthetic entity kind used for section-level attributes and status.
    static let sectionKind = EntityKind("__section")

    static func propertyChange(
        capability: CapabilityID,
        schema: SectionSchema,
        entity: SnapshotEntity,
        descriptor: PropertyDescriptor,
        before: PropertyValue,
        after: PropertyValue,
        outcome: ValueComparator.Outcome,
        observedAt: Date
    ) -> Change {
        let kindDescriptor = schema.descriptor(for: entity.kind)
        let severity = SeverityEvaluator.severity(
            forPropertyChange: descriptor,
            outcome: outcome,
            before: before,
            after: after
        )

        let transition = PropertyChange(
            key: descriptor.key,
            displayName: descriptor.displayName,
            unit: descriptor.unit,
            before: before,
            after: after
        )

        return Change(
            id: ChangeID(capability: capability, identity: entity.identity, property: descriptor.key, kind: .modified),
            kind: .modified,
            capability: capability,
            sectionName: schema.displayName,
            category: schema.category,
            entity: reference(for: entity, descriptor: kindDescriptor),
            property: transition,
            severity: severity,
            confidence: outcome.confidence,
            privacy: max(descriptor.privacy, schema.privacy == .restricted ? .restricted : descriptor.privacy),
            observedAt: observedAt,
            summary: summary(entity: entity, descriptor: descriptor, transition: transition),
            detail: detail(descriptor: descriptor, outcome: outcome)
        )
    }

    static func entityChange(
        kind: ChangeKind,
        capability: CapabilityID,
        schema: SectionSchema,
        entity: SnapshotEntity,
        observedAt: Date
    ) -> Change {
        let kindDescriptor = schema.descriptor(for: entity.kind)
        let severity = SeverityEvaluator.severity(forEntityChange: kind, descriptor: kindDescriptor)
        let noun = kindDescriptor?.singularName ?? entity.kind.rawValue.humanizedIdentifier

        let summary = switch kind {
        case .added: "\(entity.displayName) added"
        case .removed: "\(entity.displayName) removed"
        case .modified: "\(entity.displayName) changed"
        case .unchanged: "\(entity.displayName) unchanged"
        }

        return Change(
            id: ChangeID(capability: capability, identity: entity.identity, property: nil, kind: kind),
            kind: kind,
            capability: capability,
            sectionName: schema.displayName,
            category: schema.category,
            entity: reference(for: entity, descriptor: kindDescriptor),
            property: nil,
            severity: severity,
            confidence: 1,
            privacy: schema.privacy,
            observedAt: observedAt,
            summary: summary,
            detail: entityDetail(noun: noun, entity: entity, descriptor: kindDescriptor)
        )
    }

    static func statusChange(
        capability: CapabilityID,
        schema: SectionSchema,
        before: CollectionStatus,
        after: CollectionStatus,
        observedAt: Date
    ) -> Change {
        let identity = EntityIdentity(kind: sectionKind, value: capability.rawValue)
        let entity = EntityReference(
            identity: identity,
            displayName: schema.displayName,
            subtitle: "Collection status",
            symbol: schema.symbol
        )
        let transition = PropertyChange(
            key: PropertyKey("__status"),
            displayName: "Collection status",
            before: .string(before.displayName),
            after: .string(after.displayName)
        )

        return Change(
            id: ChangeID(capability: capability, identity: identity, property: transition.key, kind: .modified),
            kind: .modified,
            capability: capability,
            sectionName: schema.displayName,
            category: schema.category,
            entity: entity,
            property: transition,
            severity: SeverityEvaluator.severity(forStatusChange: before, after: after),
            confidence: 1,
            privacy: .public,
            observedAt: observedAt,
            summary: "\(schema.displayName) \(before.displayName.lowercased()) → \(after.displayName.lowercased())",
            detail: after.isProblem
                ? "Diffuse could not read this section in the later snapshot, so its contents are not compared."
                : nil
        )
    }

    static func sectionPresenceChange(
        kind: ChangeKind,
        capability: CapabilityID,
        schema: SectionSchema,
        observedAt: Date
    ) -> Change {
        let identity = EntityIdentity(kind: sectionKind, value: capability.rawValue)
        let entity = EntityReference(
            identity: identity,
            displayName: schema.displayName,
            subtitle: schema.summary,
            symbol: schema.symbol
        )

        let summary = kind == .added
            ? "\(schema.displayName) is now being collected"
            : "\(schema.displayName) is no longer being collected"

        return Change(
            id: ChangeID(capability: capability, identity: identity, property: nil, kind: kind),
            kind: kind,
            capability: capability,
            sectionName: schema.displayName,
            category: schema.category,
            entity: entity,
            property: nil,
            severity: kind == .added ? .informational : .notable,
            confidence: 1,
            privacy: .public,
            observedAt: observedAt,
            summary: summary,
            detail: kind == .added
                ? "This capability appeared between the two snapshots, so there is nothing to compare it against yet."
                : "This capability was present in the earlier snapshot but absent from the later one."
        )
    }

    // MARK: - Text

    private static func summary(
        entity: SnapshotEntity,
        descriptor: PropertyDescriptor,
        transition: PropertyChange
    ) -> String {
        let values = transition.formatted(style: .compact)
        if descriptor.isPrimary {
            return "\(entity.displayName) \(values)"
        }
        return "\(entity.displayName) · \(descriptor.displayName) \(values)"
    }

    private static func detail(descriptor: PropertyDescriptor, outcome: ValueComparator.Outcome) -> String? {
        var parts: [String] = []
        if let summary = descriptor.summary {
            parts.append(summary)
        }
        if let transition = outcome.versionTransition, transition != .unchanged {
            parts.append("Semantic version change: \(transition.rawValue).")
        }
        if outcome.confidence < 1 {
            let percent = Int((outcome.confidence * 100).rounded())
            parts.append("Close to the noise threshold for this property (\(percent)% confidence).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func entityDetail(
        noun: String,
        entity: SnapshotEntity,
        descriptor: EntityKindDescriptor?
    ) -> String? {
        let primaries = descriptor?.primaryProperties ?? []
        let described = primaries.compactMap { property -> String? in
            let value = entity[property.key]
            guard !value.isAbsent else { return nil }
            return "\(property.displayName) \(value.formatted(style: .compact))"
        }
        if described.isEmpty {
            return noun
        }
        return "\(noun) — " + described.joined(separator: ", ")
    }

    static func reference(for entity: SnapshotEntity, descriptor: EntityKindDescriptor?) -> EntityReference {
        EntityReference(
            identity: entity.identity,
            displayName: entity.displayName,
            subtitle: entity.subtitle,
            symbol: descriptor?.symbol ?? "circle.grid.2x2"
        )
    }
}
