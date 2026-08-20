import DiffuseModels
import Foundation

/// Turns a raw difference into a severity.
///
/// The baseline always comes from the schema — the capability author declares
/// what matters. The evaluator then applies a small set of *generic* rules that
/// depend only on the shape of the change, never on which capability produced
/// it. A major version jump escalating is true of Node, Python and Terraform
/// alike, so it belongs here rather than in each collector.
public enum SeverityEvaluator {
    public static func severity(
        forPropertyChange descriptor: PropertyDescriptor,
        outcome: ValueComparator.Outcome,
        before: PropertyValue,
        after: PropertyValue
    ) -> ChangeSeverity {
        var severity = descriptor.severity

        // A value appearing or disappearing is more interesting than it merely
        // moving, because it usually means something was installed or removed.
        if before.isAbsent != after.isAbsent {
            severity = severity.escalated()
        }

        if let transition = outcome.versionTransition {
            switch transition {
            case .major, .downgrade:
                severity = severity.escalated()
            case .patch, .prerelease:
                severity = severity.deescalated()
            case .minor, .unchanged:
                break
            }
        }

        // A tolerance-based comparison that only just crossed its threshold is
        // reported, but quietly.
        if outcome.confidence < 0.7 {
            severity = severity.deescalated()
        } else if let magnitude = outcome.relativeMagnitude, magnitude >= 0.25 {
            severity = severity.escalated()
        }

        return severity
    }

    public static func severity(
        forEntityChange kind: ChangeKind,
        descriptor: EntityKindDescriptor?
    ) -> ChangeSeverity {
        switch kind {
        case .added: descriptor?.additionSeverity ?? .notable
        case .removed: descriptor?.removalSeverity ?? .significant
        case .modified: .notable
        case .unchanged: .informational
        }
    }

    /// Severity for a section whose collection status changed between the two
    /// snapshots. Losing access to data is more serious than gaining it.
    public static func severity(
        forStatusChange before: CollectionStatus,
        after: CollectionStatus
    ) -> ChangeSeverity {
        if after == .permissionRequired, before != .permissionRequired {
            return .significant
        }
        if before.hasData, !after.hasData {
            return .notable
        }
        if !before.hasData, after.hasData {
            return .informational
        }
        return .informational
    }
}
