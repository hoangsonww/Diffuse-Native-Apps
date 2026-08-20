import DiffuseModels
import Foundation

/// Computes the semantic difference between two snapshots.
///
/// The engine is pure: same inputs, same output, no clock, no I/O, no platform
/// APIs. It also contains no knowledge of any specific capability — everything
/// it needs arrives inside the snapshots themselves via `SectionSchema`. That
/// is the property that makes "add a new capability" a localized change.
public struct DiffEngine: Sendable {
    public let options: DiffOptions

    public init(options: DiffOptions = .default) {
        self.options = options
    }

    // MARK: - Entry point

    public func diff(base: Snapshot, target: Snapshot) -> DiffResult {
        let capabilities = orderedCapabilities(base: base, target: target)

        var sectionDiffs: [SectionDiff] = []
        var asymmetric: [CapabilityID] = []

        for capability in capabilities {
            let baseSection = base.section(for: capability)
            let targetSection = target.section(for: capability)

            if baseSection == nil || targetSection == nil {
                asymmetric.append(capability)
            }

            if let sectionDiff = diffSection(
                base: baseSection,
                target: targetSection,
                fallbackDate: target.capturedAt
            ) {
                sectionDiffs.append(sectionDiff)
            }
        }

        let allChanges = sectionDiffs.flatMap(\.changes)
        let summary = makeSummary(
            changes: allChanges,
            sectionDiffs: sectionDiffs,
            asymmetric: asymmetric,
            elapsed: target.capturedAt.timeIntervalSince(base.capturedAt)
        )

        let clusters = ChangeCorrelator.cluster(
            allChanges.filter { $0.kind != .unchanged },
            window: options.correlationWindow,
            minimumSize: options.minimumClusterSize
        )

        return DiffResult(
            base: base.reference,
            target: target.reference,
            // Derived from the inputs rather than from `Date()` so that
            // diffing the same pair twice produces identical bytes.
            generatedAt: target.capturedAt,
            summary: summary,
            sectionDiffs: sectionDiffs.sorted { ($0.category, $0.displayName) < ($1.category, $1.displayName) },
            clusters: clusters
        )
    }

    /// Diffs a snapshot against itself, which by construction yields no
    /// changes. Exposed because it reads better than `diff(base: a, target: a)`
    /// at call sites that are asserting the identity property.
    public func selfDiff(_ snapshot: Snapshot) -> DiffResult {
        diff(base: snapshot, target: snapshot)
    }

    // MARK: - Sections

    func diffSection(
        base: SnapshotSection?,
        target: SnapshotSection?,
        fallbackDate: Date
    ) -> SectionDiff? {
        guard base != nil || target != nil else { return nil }

        let schema = target?.schema ?? base?.schema
        guard let schema, let capability = (target?.capability ?? base?.capability) else { return nil }

        let observedAt = target?.collectedAt ?? fallbackDate
        var changes: [Change] = []
        var unchangedCount = 0

        switch (base, target) {
        case let (nil, section?):
            // A capability that only exists in the later snapshot. Reporting
            // every one of its entities as "added" would bury the real signal,
            // so the appearance itself is the change.
            changes.append(
                ChangeBuilder.sectionPresenceChange(
                    kind: .added,
                    capability: capability,
                    schema: schema,
                    observedAt: section.collectedAt
                )
            )

        case let (section?, nil):
            changes.append(
                ChangeBuilder.sectionPresenceChange(
                    kind: .removed,
                    capability: capability,
                    schema: schema,
                    observedAt: fallbackDate
                )
            )
            _ = section

        case let (baseSection?, targetSection?):
            if options.includeStatusChanges, baseSection.status != targetSection.status {
                changes.append(
                    ChangeBuilder.statusChange(
                        capability: capability,
                        schema: schema,
                        before: baseSection.status,
                        after: targetSection.status,
                        observedAt: observedAt
                    )
                )
            }

            if baseSection.status.hasData, targetSection.status.hasData {
                let result = diffEntities(
                    capability: capability,
                    schema: schema,
                    base: baseSection,
                    target: targetSection,
                    observedAt: observedAt
                )
                changes.append(contentsOf: result.changes)
                unchangedCount = result.unchangedCount
            } else if !baseSection.status.hasData, targetSection.status.hasData {
                // Permission granted, skip→collect, or a background skip that
                // a foreground capture filled in: the entities are new to the
                // timeline even though the section was already present.
                let result = diffEntities(
                    capability: capability,
                    schema: schema,
                    base: baseSection,
                    target: targetSection,
                    observedAt: observedAt
                )
                changes.append(contentsOf: result.changes)
                unchangedCount = result.unchangedCount
            }

        case (nil, nil):
            return nil
        }

        let filtered = changes.filter { change in
            change.kind == .unchanged || change.severity >= options.minimumSeverity
        }

        return SectionDiff(
            capability: capability,
            displayName: schema.displayName,
            category: schema.category,
            symbol: schema.symbol,
            baseStatus: base?.status,
            targetStatus: target?.status,
            changes: filtered.sortedForPresentation(),
            unchangedEntityCount: unchangedCount
        )
    }

    // MARK: - Entities

    private struct EntityDiffResult {
        var changes: [Change]
        var unchangedCount: Int
    }

    private func diffEntities(
        capability: CapabilityID,
        schema: SectionSchema,
        base: SnapshotSection,
        target: SnapshotSection,
        observedAt: Date
    ) -> EntityDiffResult {
        let normalizedBase = SnapshotNormalizer.normalize(base, includeChildren: options.includeChildren)
        let normalizedTarget = SnapshotNormalizer.normalize(target, includeChildren: options.includeChildren)
        let match = EntityMatcher.match(base: normalizedBase, target: normalizedTarget)

        var changes: [Change] = []
        var unchangedCount = 0

        for identity in match.added {
            guard let entity = normalizedTarget.entities[identity] else { continue }
            changes.append(
                ChangeBuilder.entityChange(
                    kind: .added,
                    capability: capability,
                    schema: schema,
                    entity: entity,
                    observedAt: observedAt
                )
            )
        }

        for identity in match.removed {
            guard let entity = normalizedBase.entities[identity] else { continue }
            changes.append(
                ChangeBuilder.entityChange(
                    kind: .removed,
                    capability: capability,
                    schema: schema,
                    entity: entity,
                    observedAt: observedAt
                )
            )
        }

        for identity in match.common {
            guard
                let beforeEntity = normalizedBase.entities[identity],
                let afterEntity = normalizedTarget.entities[identity]
            else { continue }

            let entityChanges = diffProperties(
                capability: capability,
                schema: schema,
                before: beforeEntity,
                after: afterEntity,
                observedAt: observedAt
            )

            if entityChanges.isEmpty {
                unchangedCount += 1
                if options.includeUnchanged {
                    changes.append(
                        ChangeBuilder.entityChange(
                            kind: .unchanged,
                            capability: capability,
                            schema: schema,
                            entity: afterEntity,
                            observedAt: observedAt
                        )
                    )
                }
            } else {
                changes.append(contentsOf: entityChanges)
            }
        }

        changes.append(
            contentsOf: diffSectionAttributes(
                capability: capability,
                schema: schema,
                before: normalizedBase.attributes,
                after: normalizedTarget.attributes,
                observedAt: observedAt
            )
        )

        return EntityDiffResult(changes: changes, unchangedCount: unchangedCount)
    }

    private func diffProperties(
        capability: CapabilityID,
        schema: SectionSchema,
        before: SnapshotEntity,
        after: SnapshotEntity,
        observedAt: Date
    ) -> [Change] {
        var changes: [Change] = []

        let keys = Set(before.properties.keys).union(after.properties.keys).sorted()
        for key in keys {
            let descriptor = schema.descriptor(for: key, in: after.kind)
            let beforeValue = before[key]
            let afterValue = after[key]
            let outcome = ValueComparator.compare(beforeValue, afterValue, rule: descriptor.comparison)
            guard !outcome.areEqual else { continue }

            changes.append(
                ChangeBuilder.propertyChange(
                    capability: capability,
                    schema: schema,
                    entity: after,
                    descriptor: descriptor,
                    before: beforeValue,
                    after: afterValue,
                    outcome: outcome,
                    observedAt: observedAt
                )
            )
        }

        // A stable identity with a new display name is a real change — a
        // renamed volume, a relabelled display. Two caveats. Whitespace
        // differences are formatting noise from the collector rather than a
        // rename, and collectors usually derive the display name from a
        // property they also report, so emitting both would say
        // "Home → Office" twice.
        let beforeName = before.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let afterName = after.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if beforeName != afterName {
            let alreadyExplained = changes.contains { change in
                guard let property = change.property else { return false }
                return property.before.stringValue == beforeName
                    && property.after.stringValue == afterName
            }

            if !alreadyExplained {
                let descriptor = PropertyDescriptor(
                    key: ChangeBuilder.displayNameKey,
                    displayName: "Name",
                    severity: .notable,
                    privacy: schema.privacy,
                    isPrimary: true
                )
                changes.insert(
                    ChangeBuilder.propertyChange(
                        capability: capability,
                        schema: schema,
                        entity: after,
                        descriptor: descriptor,
                        before: .string(beforeName),
                        after: .string(afterName),
                        outcome: .different(),
                        observedAt: observedAt
                    ),
                    at: 0
                )
            }
        }

        return changes
    }

    private func diffSectionAttributes(
        capability: CapabilityID,
        schema: SectionSchema,
        before: [PropertyKey: PropertyValue],
        after: [PropertyKey: PropertyValue],
        observedAt: Date
    ) -> [Change] {
        let keys = Set(before.keys).union(after.keys).sorted()
        guard !keys.isEmpty else { return [] }

        let identity = EntityIdentity(kind: ChangeBuilder.sectionKind, value: capability.rawValue)
        let carrier = SnapshotEntity(
            identity: identity,
            displayName: schema.displayName,
            subtitle: "Section totals"
        )

        return keys.compactMap { key -> Change? in
            let descriptor = schema.attributeDescriptor(for: key)
                ?? PropertyDescriptor(
                    key: key,
                    displayName: key.rawValue.humanizedIdentifier,
                    severity: .informational,
                    privacy: schema.privacy
                )
            let beforeValue = before[key] ?? .absent
            let afterValue = after[key] ?? .absent
            let outcome = ValueComparator.compare(beforeValue, afterValue, rule: descriptor.comparison)
            guard !outcome.areEqual else { return nil }

            return ChangeBuilder.propertyChange(
                capability: capability,
                schema: schema,
                entity: carrier,
                descriptor: descriptor,
                before: beforeValue,
                after: afterValue,
                outcome: outcome,
                observedAt: observedAt
            )
        }
    }

    // MARK: - Support

    private func orderedCapabilities(base: Snapshot, target: Snapshot) -> [CapabilityID] {
        var seen = Set<CapabilityID>()
        var result: [CapabilityID] = []
        for capability in base.capabilities + target.capabilities where options.allows(capability) {
            if seen.insert(capability).inserted {
                result.append(capability)
            }
        }
        return result.sorted()
    }

    private func makeSummary(
        changes: [Change],
        sectionDiffs: [SectionDiff],
        asymmetric: [CapabilityID],
        elapsed: TimeInterval
    ) -> DiffSummary {
        let reportable = changes.filter { $0.kind != .unchanged }

        var bySeverity: [ChangeSeverity: Int] = [:]
        var byKind: [ChangeKind: Int] = [:]
        for change in reportable {
            bySeverity[change.severity, default: 0] += 1
            byKind[change.kind, default: 0] += 1
        }

        return DiffSummary(
            totalChanges: reportable.count,
            countsBySeverity: bySeverity,
            countsByKind: byKind,
            changedSections: sectionDiffs.count { !$0.changes.filter { $0.kind != .unchanged }.isEmpty },
            comparedSections: sectionDiffs.count,
            asymmetricSections: asymmetric.sorted(),
            elapsed: elapsed
        )
    }
}

private extension ValueComparator.Outcome {
    static func different() -> ValueComparator.Outcome {
        ValueComparator.Outcome(areEqual: false, confidence: 1, versionTransition: nil, relativeMagnitude: nil)
    }
}
