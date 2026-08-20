import Foundation

/// The stable identity of an observed thing.
///
/// Identity is what lets Diffuse tell "the same display at a new resolution"
/// apart from "one display removed, another added". Every collector is
/// responsible for choosing an identifier that survives across snapshots:
/// a display's hardware ID, an interface's BSD name, an app's bundle ID, a
/// repository's normalized path.
public struct EntityIdentity: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    /// The kind of thing being identified. Two entities of different kinds are
    /// never the same entity, even if their raw values collide.
    public let kind: EntityKind

    /// The normalized identifying value.
    public let value: String

    /// Optional disambiguator for entities that are only unique within a scope,
    /// e.g. a Git branch within a repository.
    public let scope: String?

    public init(kind: EntityKind, value: String, scope: String? = nil) {
        self.kind = kind
        self.value = Self.normalize(value)
        self.scope = scope.map(Self.normalize)
    }

    /// Builds an identity from a filesystem path, collapsing the home
    /// directory and trailing separators so the same repository observed via
    /// `/Users/me/dev/app` and `~/dev/app/` matches.
    public static func path(kind: EntityKind, path: String, scope: String? = nil) -> EntityIdentity {
        EntityIdentity(kind: kind, value: normalizePath(path), scope: scope)
    }

    public var description: String {
        if let scope {
            return "\(kind.rawValue):\(scope)/\(value)"
        }
        return "\(kind.rawValue):\(value)"
    }

    /// A stable, filename-safe token used in change identifiers and fixtures.
    public var token: String {
        description
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "-")
    }

    public static func < (lhs: EntityIdentity, rhs: EntityIdentity) -> Bool {
        (lhs.kind, lhs.scope ?? "", lhs.value) < (rhs.kind, rhs.scope ?? "", rhs.value)
    }

    // MARK: - Normalization

    /// Collapses whitespace and case so trivial formatting differences between
    /// two collector runs do not read as an identity change.
    public static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .lowercased()
    }

    public static func normalizePath(_ path: String) -> String {
        var text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = NSHomeDirectory()
        if !home.isEmpty, text.hasPrefix(home) {
            text = "~" + text.dropFirst(home.count)
        }
        while text.count > 1, text.hasSuffix("/") {
            text.removeLast()
        }
        return normalize(text)
    }
}

/// A lightweight, self-contained reference to an entity, embedded in changes so
/// that a `DiffResult` can be rendered or exported without the source snapshots.
public struct EntityReference: Sendable, Hashable, Codable {
    public let identity: EntityIdentity
    public let displayName: String
    public let subtitle: String?
    public let symbol: String

    public init(identity: EntityIdentity, displayName: String, subtitle: String? = nil, symbol: String) {
        self.identity = identity
        self.displayName = displayName
        self.subtitle = subtitle
        self.symbol = symbol
    }
}
