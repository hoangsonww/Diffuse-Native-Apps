import Foundation

/// How much a change matters.
///
/// Severity is declared by the capability that owns the property, not by the
/// UI. That keeps "a Node minor version bump is significant, a two-percent
/// battery drop is not" as domain knowledge rather than presentation logic.
public enum ChangeSeverity: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    /// Expected drift. Battery level, free space wobble, process counts.
    case informational

    /// Worth knowing but rarely the answer to "what broke".
    case notable

    /// The kind of change that explains a behaviour difference.
    case significant

    /// Something the user almost certainly wants to act on.
    case critical

    public static func < (lhs: ChangeSeverity, rhs: ChangeSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .informational: 0
        case .notable: 1
        case .significant: 2
        case .critical: 3
        }
    }

    public var displayName: String {
        switch self {
        case .informational: "Informational"
        case .notable: "Notable"
        case .significant: "Significant"
        case .critical: "Critical"
        }
    }

    public var symbol: String {
        switch self {
        case .informational: "circle"
        case .notable: "circle.lefthalf.filled"
        case .significant: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    /// Severities at least as important as the receiver.
    public var andAbove: [ChangeSeverity] {
        Self.allCases.filter { $0 >= self }
    }

    /// One step up, saturating at `.critical`. Used by escalation rules.
    public func escalated() -> ChangeSeverity {
        switch self {
        case .informational: .notable
        case .notable: .significant
        case .significant, .critical: .critical
        }
    }

    /// One step down, saturating at `.informational`.
    public func deescalated() -> ChangeSeverity {
        switch self {
        case .informational, .notable: .informational
        case .significant: .notable
        case .critical: .significant
        }
    }
}

/// Keeps `[ChangeSeverity: Int]` encoding as a JSON object instead of a
/// flattened key/value array, so summary counts stay readable on disk.
extension ChangeSeverity: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// Whether an entity or property appeared, disappeared or changed value.
public enum ChangeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case added
    case removed
    case modified

    /// Emitted only when a diff is requested with `includeUnchanged`.
    case unchanged

    public var displayName: String {
        switch self {
        case .added: "Added"
        case .removed: "Removed"
        case .modified: "Changed"
        case .unchanged: "Unchanged"
        }
    }

    public var symbol: String {
        switch self {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .modified: "arrow.triangle.2.circlepath"
        case .unchanged: "equal.circle"
        }
    }

    public var verb: String {
        switch self {
        case .added: "appeared"
        case .removed: "disappeared"
        case .modified: "changed"
        case .unchanged: "stayed the same"
        }
    }
}

extension ChangeKind: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(rawValue: codingKey.stringValue)
    }
}
