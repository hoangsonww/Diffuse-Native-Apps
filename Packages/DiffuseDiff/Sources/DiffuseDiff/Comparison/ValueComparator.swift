import DiffuseModels
import Foundation

/// Applies a schema-declared `ComparisonRule` to a pair of values.
///
/// This is the only place in Diffuse that decides whether two readings are
/// "the same". Because the rule arrives with the data, adding a capability
/// never requires touching this file.
public enum ValueComparator {
    public struct Outcome: Sendable, Hashable {
        public let areEqual: Bool

        /// How confident the engine is that a reported difference is real
        /// rather than measurement noise. Always `1` for exact comparisons.
        public let confidence: Double

        /// Set when a semantic version rule detected a meaningful transition.
        public let versionTransition: SemanticVersion.Transition?

        /// Fractional magnitude of a numeric change, where available. Used by
        /// severity escalation.
        public let relativeMagnitude: Double?

        static let equal = Outcome(areEqual: true, confidence: 1, versionTransition: nil, relativeMagnitude: nil)

        static func different(
            confidence: Double = 1,
            versionTransition: SemanticVersion.Transition? = nil,
            relativeMagnitude: Double? = nil
        ) -> Outcome {
            Outcome(
                areEqual: false,
                confidence: min(max(confidence, 0), 1),
                versionTransition: versionTransition,
                relativeMagnitude: relativeMagnitude
            )
        }
    }

    public static func compare(
        _ before: PropertyValue,
        _ after: PropertyValue,
        rule: ComparisonRule
    ) -> Outcome {
        if case .ignored = rule {
            return .equal
        }

        // An appearing or disappearing value is always a real difference, no
        // matter how lenient the rule is.
        switch (before.isAbsent, after.isAbsent) {
        case (true, true): return .equal
        case (true, false), (false, true): return .different()
        case (false, false): break
        }

        switch rule {
        case .exact:
            return before == after ? .equal : .different()

        case .caseInsensitive:
            guard let left = before.stringValue, let right = after.stringValue else {
                return before == after ? .equal : .different()
            }
            return left.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(right.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                ? .equal
                : .different()

        case .pathNormalized:
            guard let left = before.stringValue, let right = after.stringValue else {
                return before == after ? .equal : .different()
            }
            return EntityIdentity.normalizePath(left) == EntityIdentity.normalizePath(right)
                ? .equal
                : .different()

        case .semanticVersion:
            guard let left = before.versionValue, let right = after.versionValue else {
                // Not parseable as versions on at least one side: fall back to
                // a literal comparison rather than declaring them equal.
                return before == after ? .equal : .different()
            }
            guard !left.hasSamePrecedence(as: right) else { return .equal }
            return .different(versionTransition: left.transition(to: right))

        case let .numeric(tolerance):
            return compareNumeric(before, after, tolerance: tolerance, isRelative: false)

        case let .relative(tolerance):
            return compareNumeric(before, after, tolerance: tolerance, isRelative: true)

        case .unordered:
            guard let left = before.listValue, let right = after.listValue else {
                return before == after ? .equal : .different()
            }
            let leftKeys = left.map(\.searchText).sorted()
            let rightKeys = right.map(\.searchText).sorted()
            return leftKeys == rightKeys ? .equal : .different()

        case .ignored:
            return .equal
        }
    }

    private static func compareNumeric(
        _ before: PropertyValue,
        _ after: PropertyValue,
        tolerance: Double,
        isRelative: Bool
    ) -> Outcome {
        guard let left = before.numericValue, let right = after.numericValue else {
            return before == after ? .equal : .different()
        }

        let delta = abs(right - left)
        let scale = max(abs(left), abs(right))
        let magnitude = scale > 0 ? delta / scale : (delta > 0 ? 1 : 0)
        let threshold = isRelative ? tolerance * scale : tolerance

        if delta <= threshold {
            return .equal
        }

        // Just beyond the threshold is plausibly noise; far beyond it is not.
        // Confidence ramps from 0.5 at the threshold to 1.0 at 3x the threshold.
        let confidence: Double
        if threshold > 0 {
            let ratio = delta / threshold
            confidence = min(1, 0.5 + 0.25 * (ratio - 1))
        } else {
            confidence = 1
        }

        return .different(confidence: confidence, relativeMagnitude: magnitude)
    }
}
