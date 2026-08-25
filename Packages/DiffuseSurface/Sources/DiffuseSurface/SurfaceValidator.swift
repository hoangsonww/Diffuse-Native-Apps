import Foundation

/// Why a surface cannot be rendered by this build.
public enum SurfaceIncompatibility: Sendable, Hashable, CustomStringConvertible {
    /// The payload was written against a newer node contract.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    /// The payload declares it needs a newer app than this one.
    case requiresNewerApp(minimum: String, running: String)

    /// Nothing would render even if it were compatible.
    case empty

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            "Surface schema version \(found) is newer than this build supports (\(supported))."
        case let .requiresNewerApp(minimum, running):
            "Surface requires app version \(minimum); this build is \(running)."
        case .empty:
            "Surface contains no renderable nodes."
        }
    }
}

/// A non-fatal problem found while checking a surface. Problems describe nodes
/// that will be *skipped*; they never prevent the rest from rendering.
public struct SurfaceProblem: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: Sendable, Hashable {
        case unknownNodeType(SurfaceNodeType)
        case missingRequiredProperty(String)
        case unhandledAction(String)
        case duplicateNodeID(String)
    }

    public let nodeID: String
    public let kind: Kind

    public init(nodeID: String, kind: Kind) {
        self.nodeID = nodeID
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case let .unknownNodeType(type): "\(nodeID): unknown node type '\(type)'."
        case let .missingRequiredProperty(key): "\(nodeID): missing required property '\(key)'."
        case let .unhandledAction(name): "\(nodeID): no handler registered for action '\(name)'."
        case let .duplicateNodeID(id): "\(nodeID): duplicate node id '\(id)'."
        }
    }
}

/// Checks a surface against what this build can actually render.
///
/// Split from the renderer on purpose: the same rules run in tests, in the CLI,
/// and in a future publishing pipeline that wants to reject a bad payload
/// *before* it reaches a device.
public enum SurfaceValidator {
    /// Properties a node type cannot render without.
    public static let requiredProperties: [SurfaceNodeType: [String]] = [
        .heading: ["text"],
        .paragraph: ["text"],
        .bullets: ["items"],
        .callout: ["text"],
        .button: ["title"],
    ]

    /// Whether this build can render the surface at all.
    public static func compatibility(
        of surface: Surface,
        appVersion: String,
        supportedSchemaVersion: Int = Surface.currentSchemaVersion
    ) -> SurfaceIncompatibility? {
        if surface.schemaVersion > supportedSchemaVersion {
            return .unsupportedSchemaVersion(found: surface.schemaVersion, supported: supportedSchemaVersion)
        }
        if let minimum = surface.minimumAppVersion,
           compare(minimum, isNewerThan: appVersion) {
            return .requiresNewerApp(minimum: minimum, running: appVersion)
        }
        if surface.nodes.isEmpty {
            return .empty
        }
        return nil
    }

    /// Node-level problems. Each one costs that node, not the surface.
    public static func problems(
        in surface: Surface,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all,
        handledActions: Set<String> = []
    ) -> [SurfaceProblem] {
        var problems: [SurfaceProblem] = []
        var seenIDs = Set<String>()

        for node in surface.flattenedNodes {
            if !seenIDs.insert(node.id).inserted {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .duplicateNodeID(node.id)))
            }
            guard supportedTypes.contains(node.type) else {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .unknownNodeType(node.type)))
                continue
            }
            for key in requiredProperties[node.type] ?? [] where node.properties[key] == nil {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .missingRequiredProperty(key)))
            }
            if let action = node.action, !handledActions.isEmpty, !handledActions.contains(action.name) {
                problems.append(SurfaceProblem(nodeID: node.id, kind: .unhandledAction(action.name)))
            }
        }
        return problems
    }

    /// The nodes that survive validation, with unrenderable ones pruned.
    ///
    /// A parent whose children are all dropped still renders if it is itself
    /// valid — an empty group is harmless, a crash is not.
    public static func renderable(
        _ nodes: [SurfaceNode],
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all
    ) -> [SurfaceNode] {
        nodes.compactMap { node in
            guard supportedTypes.contains(node.type) else { return nil }
            for key in requiredProperties[node.type] ?? [] where node.properties[key] == nil {
                return nil
            }
            return SurfaceNode(
                id: node.id,
                type: node.type,
                properties: node.properties,
                children: renderable(node.children, supportedTypes: supportedTypes),
                action: node.action
            )
        }
    }

    /// Dotted-version comparison that does not depend on the snapshot engine's
    /// `SemanticVersion` — this package deliberately has no dependencies.
    ///
    /// Public because it decides whether a payload renders at all, so a
    /// publishing pipeline needs to apply exactly this rule before shipping.
    public static func compare(_ lhs: String, isNewerThan rhs: String) -> Bool {
        let left = components(of: lhs)
        let right = components(of: rhs)
        for index in 0 ..< max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a > b
            }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
