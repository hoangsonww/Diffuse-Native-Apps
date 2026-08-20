import Foundation

/// A single observed value.
///
/// Collectors work with strongly typed Swift structs; those structs project
/// into `PropertyValue` so that storage, diffing, search and presentation can
/// be written once instead of once per capability. The case carries the
/// *semantics* of the number (bytes vs. seconds vs. a plain count) so that
/// formatting and comparison do not need an out-of-band unit lookup.
public enum PropertyValue: Sendable, Hashable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)

    /// A byte count, formatted with a binary/decimal unit on display.
    case bytes(Int64)

    /// A duration in seconds.
    case duration(TimeInterval)

    /// A ratio in `0...1`, formatted as a percentage.
    case percentage(Double)

    case date(Date)
    case version(SemanticVersion)

    /// An opaque stable identifier (UUID, bundle ID, hardware ID). Never
    /// treated as human-readable prose by the formatter.
    case identifier(String)

    /// A filesystem path. Held separately from `string` so comparison can
    /// normalize trailing slashes and the home directory.
    case path(String)

    case list([PropertyValue])

    /// The property is defined for this entity kind but has no value right now.
    case absent

    // MARK: - Convenience

    public var isAbsent: Bool {
        if case .absent = self {
            return true
        }
        return false
    }

    public var stringValue: String? {
        switch self {
        case let .string(value), let .identifier(value), let .path(value): value
        case let .version(value): value.description
        default: nil
        }
    }

    public var numericValue: Double? {
        switch self {
        case let .integer(value): Double(value)
        case let .double(value): value
        case let .bytes(value): Double(value)
        case let .duration(value): value
        case let .percentage(value): value
        case let .boolean(value): value ? 1 : 0
        case let .date(value): value.timeIntervalSince1970
        default: nil
        }
    }

    public var versionValue: SemanticVersion? {
        switch self {
        case let .version(value): value
        case let .string(value), let .identifier(value): SemanticVersion(value)
        default: nil
        }
    }

    public var listValue: [PropertyValue]? {
        if case let .list(values) = self {
            return values
        }
        return nil
    }

    /// A short discriminator used in serialization and in schema validation.
    public var typeName: String {
        switch self {
        case .string: "string"
        case .integer: "integer"
        case .double: "double"
        case .boolean: "boolean"
        case .bytes: "bytes"
        case .duration: "duration"
        case .percentage: "percentage"
        case .date: "date"
        case .version: "version"
        case .identifier: "identifier"
        case .path: "path"
        case .list: "list"
        case .absent: "absent"
        }
    }

    /// Text used for full-text search indexing. Deliberately unformatted so
    /// that searching for `24.6.0` matches regardless of display style.
    public var searchText: String {
        switch self {
        case let .string(value), let .identifier(value), let .path(value): value
        case let .integer(value): String(value)
        case let .bytes(value): String(value)
        case let .double(value): String(value)
        case let .duration(value): String(value)
        case let .percentage(value): String(value)
        case let .boolean(value): value ? "true yes enabled on" : "false no disabled off"
        case let .version(value): value.description
        case let .date(value): ISO8601DateFormatter().string(from: value)
        case let .list(values): values.map(\.searchText).joined(separator: " ")
        case .absent: ""
        }
    }
}

// MARK: - Literals

extension PropertyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension PropertyValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }
}

extension PropertyValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension PropertyValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

// MARK: - Codable

extension PropertyValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "string": self = try .string(container.decode(String.self, forKey: .value))
        case "integer": self = try .integer(container.decode(Int64.self, forKey: .value))
        case "double": self = try .double(container.decode(Double.self, forKey: .value))
        case "boolean": self = try .boolean(container.decode(Bool.self, forKey: .value))
        case "bytes": self = try .bytes(container.decode(Int64.self, forKey: .value))
        case "duration": self = try .duration(container.decode(Double.self, forKey: .value))
        case "percentage": self = try .percentage(container.decode(Double.self, forKey: .value))
        case "date": self = try .date(container.decode(Date.self, forKey: .value))
        case "version": self = try .version(container.decode(SemanticVersion.self, forKey: .value))
        case "identifier": self = try .identifier(container.decode(String.self, forKey: .value))
        case "path": self = try .path(container.decode(String.self, forKey: .value))
        case "list": self = try .list(container.decode([PropertyValue].self, forKey: .value))
        case "absent": self = .absent
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown property value type '\(type)'"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)

        switch self {
        case let .string(value), let .identifier(value), let .path(value):
            try container.encode(value, forKey: .value)
        case let .integer(value), let .bytes(value):
            try container.encode(value, forKey: .value)
        case let .double(value), let .duration(value), let .percentage(value):
            try container.encode(value, forKey: .value)
        case let .boolean(value):
            try container.encode(value, forKey: .value)
        case let .date(value):
            try container.encode(value, forKey: .value)
        case let .version(value):
            try container.encode(value, forKey: .value)
        case let .list(values):
            try container.encode(values, forKey: .value)
        case .absent:
            break
        }
    }
}

// MARK: - Formatting

public extension PropertyValue {
    /// A human-readable rendering suitable for both the UI and CLI output.
    func formatted(style: PropertyFormatStyle = .standard) -> String {
        switch self {
        case let .string(value):
            return value
        case let .identifier(value):
            return value
        case let .path(value):
            return style == .compact ? (value as NSString).lastPathComponent : value
        case let .integer(value):
            return value.formatted(.number)
        case let .double(value):
            return value.formatted(.number.precision(.fractionLength(0 ... 2)))
        case let .boolean(value):
            return value ? "On" : "Off"
        case let .bytes(value):
            return value.formatted(.byteCount(style: .file))
        case let .duration(value):
            return Self.durationText(value)
        case let .percentage(value):
            return value.formatted(.percent.precision(.fractionLength(0 ... 1)))
        case let .date(value):
            return value.formatted(date: .abbreviated, time: .shortened)
        case let .version(value):
            return value.description
        case let .list(values):
            let rendered = values.map { $0.formatted(style: style) }
            if style == .compact, rendered.count > 3 {
                return rendered.prefix(3).joined(separator: ", ") + " +\(rendered.count - 3) more"
            }
            return rendered.joined(separator: ", ")
        case .absent:
            return "—"
        }
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\((seconds * 1000).rounded().formatted(.number.precision(.fractionLength(0)))) ms"
        }
        if seconds < 60 {
            return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "\(Int(seconds)) s"
    }
}

public enum PropertyFormatStyle: Sendable, Hashable {
    case standard
    case compact
}
