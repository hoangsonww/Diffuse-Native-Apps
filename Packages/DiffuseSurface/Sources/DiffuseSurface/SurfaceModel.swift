import Foundation

/// A named screen region an app is willing to have described by data rather
/// than by code — "help", "onboarding", "announcement".
///
/// Surfaces are deliberately *additive*. Every one of them has a hand-written
/// native fallback, and a surface that is missing, malformed, or built for a
/// newer app simply does not render. Nothing a server could say can leave a
/// screen blank.
public struct SurfaceID: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: SurfaceID, rhs: SurfaceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension SurfaceID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// The kind of a node. Open rather than an enum on purpose: a build that has
/// never heard of a type must be able to *parse* it and skip it, which a closed
/// enum could not express.
public struct SurfaceNodeType: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: SurfaceNodeType, rhs: SurfaceNodeType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // The vocabulary the shipped renderers understand. A renderer declares
    // which of these it supports; anything else degrades.
    public static let heading = SurfaceNodeType("heading")
    public static let paragraph = SurfaceNodeType("paragraph")
    public static let bullets = SurfaceNodeType("bullets")
    public static let callout = SurfaceNodeType("callout")
    public static let button = SurfaceNodeType("button")
    public static let divider = SurfaceNodeType("divider")
    public static let spacer = SurfaceNodeType("spacer")
    public static let group = SurfaceNodeType("group")

    public static let all: Set<SurfaceNodeType> = [
        .heading, .paragraph, .bullets, .callout, .button, .divider, .spacer, .group,
    ]
}

extension SurfaceNodeType: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// A property value. Deliberately a small closed union rather than `Any`:
/// `Any` is not `Sendable`, not `Codable`, and not checkable.
public enum SurfaceValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([SurfaceValue])

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case let .int(value): value
        case let .double(value): Int(value)
        default: nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case let .double(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    public var listValue: [SurfaceValue]? {
        if case let .list(values) = self {
            return values
        }
        return nil
    }

    /// Every string in a list value, which is what `bullets` needs.
    public var stringListValue: [String]? {
        guard case let .list(values) = self else { return nil }
        return values.compactMap(\.stringValue)
    }
}

extension SurfaceValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension SurfaceValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension SurfaceValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension SurfaceValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool must be attempted before Int: JSONDecoder will happily decode
        // `true` as 1 on some platforms, which would turn a flag into a number.
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SurfaceValue].self) {
            self = .list(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A surface value must be a string, number, boolean, or list."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .list(values): try container.encode(values)
        }
    }
}

/// A named intent, resolved by the host against a handler map.
///
/// Actions are names, never code. A surface can ask for "capture" but cannot
/// describe *how* to capture, which is what keeps a data payload from becoming
/// an execution vector.
public struct SurfaceAction: Sendable, Hashable, Codable {
    public let name: String
    public let parameters: [String: SurfaceValue]

    public init(name: String, parameters: [String: SurfaceValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// One node in a surface tree.
public struct SurfaceNode: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let type: SurfaceNodeType
    public let properties: [String: SurfaceValue]
    public let children: [SurfaceNode]
    public let action: SurfaceAction?

    public init(
        id: String,
        type: SurfaceNodeType,
        properties: [String: SurfaceValue] = [:],
        children: [SurfaceNode] = [],
        action: SurfaceAction? = nil
    ) {
        self.id = id
        self.type = type
        self.properties = properties
        self.children = children
        self.action = action
    }

    public subscript(property key: String) -> SurfaceValue? {
        properties[key]
    }

    public func string(_ key: String) -> String? {
        properties[key]?.stringValue
    }

    /// Every node in this subtree, including this one, depth-first.
    public var flattened: [SurfaceNode] {
        [self] + children.flatMap(\.flattened)
    }
}

extension SurfaceNode {
    private enum CodingKeys: String, CodingKey {
        case id, type, properties, children, action
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(SurfaceNodeType.self, forKey: .type)
        // Absent collections decode as empty rather than failing: a payload
        // that omits `children` is the common case, not an error.
        properties = try container.decodeIfPresent([String: SurfaceValue].self, forKey: .properties) ?? [:]
        children = try container.decodeIfPresent([SurfaceNode].self, forKey: .children) ?? []
        action = try container.decodeIfPresent(SurfaceAction.self, forKey: .action)
    }
}

/// A complete described screen region.
public struct Surface: Sendable, Hashable, Codable, Identifiable {
    /// Bumped only for a breaking change to the node contract.
    public static let currentSchemaVersion = 1

    public let id: SurfaceID
    public let schemaVersion: Int

    /// The lowest app version that should render this surface. A payload aimed
    /// at a newer build is refused rather than half-rendered.
    public let minimumAppVersion: String?

    /// An opaque publisher-assigned revision, used for cache invalidation and
    /// for telling two payloads apart in diagnostics.
    public let revision: String?

    public let nodes: [SurfaceNode]

    public init(
        id: SurfaceID,
        schemaVersion: Int = Surface.currentSchemaVersion,
        minimumAppVersion: String? = nil,
        revision: String? = nil,
        nodes: [SurfaceNode]
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.minimumAppVersion = minimumAppVersion
        self.revision = revision
        self.nodes = nodes
    }

    public var flattenedNodes: [SurfaceNode] {
        nodes.flatMap(\.flattened)
    }

    /// Every action name this surface can dispatch. The host uses it to check
    /// up front that it can honour the payload.
    public var actionNames: Set<String> {
        Set(flattenedNodes.compactMap(\.action?.name))
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, minimumAppVersion, revision, nodes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SurfaceID.self, forKey: .id)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Surface.currentSchemaVersion
        minimumAppVersion = try container.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        nodes = try container.decodeIfPresent([SurfaceNode].self, forKey: .nodes) ?? []
    }
}
