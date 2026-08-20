import Foundation

/// One observed thing inside a snapshot section: a display, a network
/// interface, an installed tool, a repository.
///
/// Entities are intentionally uniform. All capability-specific meaning lives in
/// the section's schema, which describes what each property key means, how it
/// should be compared, and how significant a change to it is.
public struct SnapshotEntity: Sendable, Hashable, Codable, Identifiable {
    public let identity: EntityIdentity
    public var displayName: String
    public var subtitle: String?
    public var properties: [PropertyKey: PropertyValue]

    /// Nested entities, e.g. the branches of a repository or the volumes of a
    /// disk. Children participate in diffing exactly like top-level entities.
    public var children: [SnapshotEntity]

    /// Free-form labels used for filtering and search, e.g. `external`, `vpn`.
    public var tags: Set<String>

    public var id: EntityIdentity {
        identity
    }

    public init(
        identity: EntityIdentity,
        displayName: String,
        subtitle: String? = nil,
        properties: [PropertyKey: PropertyValue] = [:],
        children: [SnapshotEntity] = [],
        tags: Set<String> = []
    ) {
        self.identity = identity
        self.displayName = displayName
        self.subtitle = subtitle
        self.properties = properties
        self.children = children
        self.tags = tags
    }

    public init(
        kind: EntityKind,
        id value: String,
        scope: String? = nil,
        displayName: String,
        subtitle: String? = nil,
        properties: [PropertyKey: PropertyValue] = [:],
        children: [SnapshotEntity] = [],
        tags: Set<String> = []
    ) {
        self.init(
            identity: EntityIdentity(kind: kind, value: value, scope: scope),
            displayName: displayName,
            subtitle: subtitle,
            properties: properties,
            children: children,
            tags: tags
        )
    }

    public subscript(key: PropertyKey) -> PropertyValue {
        get { properties[key] ?? .absent }
        set { properties[key] = newValue }
    }

    public var kind: EntityKind {
        identity.kind
    }

    /// Property keys in a stable order. Diff output and exports must not depend
    /// on dictionary iteration order.
    public var sortedPropertyKeys: [PropertyKey] {
        properties.keys.sorted()
    }

    /// Every entity in this subtree, including the receiver, depth-first.
    public var flattened: [SnapshotEntity] {
        [self] + children.flatMap(\.flattened)
    }

    /// Text used to build the search index for this entity.
    public var searchText: String {
        var parts = [displayName, identity.value]
        if let subtitle {
            parts.append(subtitle)
        }
        parts.append(contentsOf: tags)
        parts.append(contentsOf: sortedPropertyKeys.map { properties[$0]?.searchText ?? "" })
        return parts.joined(separator: " ").lowercased()
    }

    /// Returns a copy with `transform` applied to every property value.
    /// Used by the export pipeline to apply a redaction policy.
    public func mapProperties(
        _ transform: (PropertyKey, PropertyValue) -> PropertyValue
    ) -> SnapshotEntity {
        var copy = self
        copy.properties = properties.reduce(into: [:]) { result, pair in
            result[pair.key] = transform(pair.key, pair.value)
        }
        copy.children = children.map { $0.mapProperties(transform) }
        return copy
    }
}
