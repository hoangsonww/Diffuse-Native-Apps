import Foundation

/// A lenient semantic version used for both schema versioning and for comparing
/// tool versions reported by collectors.
///
/// Real-world tools emit things like `v24.6.0`, `1.2`, `3.11.9+build.7` and
/// `2.0.0-beta.3`, so parsing is forgiving while comparison stays strict about
/// precedence: numeric identifiers compare numerically, and a pre-release
/// version has lower precedence than its associated release.
public struct SemanticVersion: Sendable, Hashable, Codable, Comparable, CustomStringConvertible,
    LosslessStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let build: [String]

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0, prerelease: [String] = [], build: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Parses a version string, tolerating a leading `v` and missing components.
    /// Returns `nil` when no leading numeric component can be found.
    public init?(_ description: String) {
        var text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var build: [String] = []
        if let plus = text.firstIndex(of: "+") {
            build = String(text[text.index(after: plus)...]).split(separator: ".").map(String.init)
            text = String(text[text.startIndex ..< plus])
        }

        var prerelease: [String] = []
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...]).split(separator: ".").map(String.init)
            text = String(text[text.startIndex ..< dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let major = Int(first) else { return nil }

        self.major = major
        minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        self.prerelease = prerelease
        self.build = build
    }

    public var description: String {
        var text = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            text += "-" + prerelease.joined(separator: ".")
        }
        if !build.isEmpty {
            text += "+" + build.joined(separator: ".")
        }
        return text
    }

    /// Build metadata is ignored for precedence, per the semver specification.
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    /// Whether two versions rank equally.
    ///
    /// Distinct from `==`, which includes build metadata. Semver says build
    /// metadata is ignored for precedence, so `2.0.0` and `2.0.0+build.9` are
    /// the same release rebuilt and must not read as an upgrade.
    public func hasSamePrecedence(as other: SemanticVersion) -> Bool {
        !(self < other) && !(other < self)
    }

    /// The relationship between two versions, used to describe upgrades and
    /// downgrades without the caller re-deriving it.
    public enum Transition: String, Sendable, Hashable, Codable {
        case major, minor, patch, prerelease, unchanged, downgrade
    }

    public func transition(to other: SemanticVersion) -> Transition {
        if hasSamePrecedence(as: other) {
            return .unchanged
        }
        if other < self {
            return .downgrade
        }
        if other.major != major {
            return .major
        }
        if other.minor != minor {
            return .minor
        }
        if other.patch != patch {
            return .patch
        }
        return .prerelease
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = SemanticVersion(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid semantic version '\(text)'"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension SemanticVersion: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = SemanticVersion(value) ?? SemanticVersion(0)
    }
}
