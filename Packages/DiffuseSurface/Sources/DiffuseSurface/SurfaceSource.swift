import Foundation

/// Where a surface description comes from.
///
/// This is the seam the whole design exists for. The app shipped today reads
/// from its own bundle and makes no network call; adding a remote publisher
/// later means conforming one new type here and changing one line of wiring,
/// with the renderer, the validator, and every test untouched.
public protocol SurfaceSource: Sendable {
    func surface(_ id: SurfaceID) async throws -> Surface?
}

/// Surfaces held in memory. The test double, and a perfectly good production
/// source for defaults compiled into the binary.
public struct InMemorySurfaceSource: SurfaceSource {
    private let surfaces: [SurfaceID: Surface]

    public init(_ surfaces: [Surface]) {
        self.surfaces = Dictionary(surfaces.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func surface(_ id: SurfaceID) async throws -> Surface? {
        surfaces[id]
    }
}

/// Surfaces decoded from JSON that ships inside the app.
///
/// The loader is a closure rather than a `Bundle` so this stays testable and so
/// the package keeps working on a platform where `Bundle.module` is awkward.
public struct BundledSurfaceSource: SurfaceSource {
    private let load: @Sendable (SurfaceID) -> Data?

    public init(load: @escaping @Sendable (SurfaceID) -> Data?) {
        self.load = load
    }

    public init(bundle: Bundle, subdirectory: String? = nil) {
        self.init { id in
            guard let url = bundle.url(forResource: id.rawValue, withExtension: "json", subdirectory: subdirectory)
            else {
                return nil
            }
            return try? Data(contentsOf: url)
        }
    }

    public func surface(_ id: SurfaceID) async throws -> Surface? {
        guard let data = load(id) else { return nil }
        return try JSONDecoder().decode(Surface.self, from: data)
    }
}

/// Tries each source in order and returns the first surface found.
///
/// The ordering is the policy: put a remote or cached source first and the
/// bundled default last, and the app degrades to something that always works
/// when everything above it is unavailable.
public struct FallbackSurfaceSource: SurfaceSource {
    private let sources: [any SurfaceSource]

    public init(_ sources: [any SurfaceSource]) {
        self.sources = sources
    }

    public func surface(_ id: SurfaceID) async throws -> Surface? {
        for source in sources {
            // A source that throws is treated as "nothing here" so one bad
            // link cannot break the chain below it.
            if let surface = try? await source.surface(id) {
                return surface
            }
        }
        return nil
    }
}

/// Caches what an upstream source returned, keyed by surface id.
///
/// An actor because a cache is shared mutable state, and because two screens
/// asking for the same surface at once is the normal case, not the edge one.
public actor CachedSurfaceSource: SurfaceSource {
    private struct Entry {
        let surface: Surface
        let storedAt: Date
    }

    private let upstream: any SurfaceSource
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [SurfaceID: Entry] = [:]

    public init(
        upstream: any SurfaceSource,
        lifetime: TimeInterval = 3600,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.upstream = upstream
        self.lifetime = lifetime
        self.now = now
    }

    public func surface(_ id: SurfaceID) async throws -> Surface? {
        if let entry = entries[id], now().timeIntervalSince(entry.storedAt) < lifetime {
            return entry.surface
        }
        guard let surface = try await upstream.surface(id) else {
            // A miss upstream must not evict a good cached copy: the whole
            // point of the cache is surviving an unavailable publisher.
            return entries[id]?.surface
        }
        entries[id] = Entry(surface: surface, storedAt: now())
        return surface
    }

    public func invalidate(_ id: SurfaceID) {
        entries[id] = nil
    }

    public func invalidateAll() {
        entries.removeAll()
    }
}

/// The result of asking for a surface and checking it against this build.
public enum SurfaceResolution: Sendable {
    /// Render these nodes. Problems are diagnostics, not failures.
    case render(Surface, problems: [SurfaceProblem])

    /// Render the app's own native UI instead.
    case fallback(reason: SurfaceFallbackReason)
}

public enum SurfaceFallbackReason: Sendable, Hashable, CustomStringConvertible {
    case notFound
    case decodingFailed(String)
    case incompatible(SurfaceIncompatibility)
    case noRenderableNodes

    public var description: String {
        switch self {
        case .notFound: "No surface was published for this id."
        case let .decodingFailed(message): "Surface could not be decoded: \(message)."
        case let .incompatible(reason): reason.description
        case .noRenderableNodes: "Every node in the surface was skipped."
        }
    }
}

/// Fetches, validates, and decides render-or-fallback in one place.
///
/// Every client goes through this rather than calling a source directly, which
/// is what guarantees the fallback rule is applied uniformly instead of being
/// re-implemented per screen.
public struct SurfaceResolver: Sendable {
    private let source: any SurfaceSource
    private let appVersion: String
    private let supportedTypes: Set<SurfaceNodeType>

    public init(
        source: any SurfaceSource,
        appVersion: String,
        supportedTypes: Set<SurfaceNodeType> = SurfaceNodeType.all
    ) {
        self.source = source
        self.appVersion = appVersion
        self.supportedTypes = supportedTypes
    }

    public func resolve(_ id: SurfaceID, handledActions: Set<String> = []) async -> SurfaceResolution {
        let fetched: Surface?
        do {
            fetched = try await source.surface(id)
        } catch {
            return .fallback(reason: .decodingFailed(String(describing: error)))
        }

        guard let surface = fetched else { return .fallback(reason: .notFound) }

        if let incompatibility = SurfaceValidator.compatibility(of: surface, appVersion: appVersion) {
            return .fallback(reason: .incompatible(incompatibility))
        }

        let problems = SurfaceValidator.problems(
            in: surface,
            supportedTypes: supportedTypes,
            handledActions: handledActions
        )
        let nodes = SurfaceValidator.renderable(surface.nodes, supportedTypes: supportedTypes)
        guard !nodes.isEmpty else { return .fallback(reason: .noRenderableNodes) }

        let pruned = Surface(
            id: surface.id,
            schemaVersion: surface.schemaVersion,
            minimumAppVersion: surface.minimumAppVersion,
            revision: surface.revision,
            nodes: nodes
        )
        return .render(pruned, problems: problems)
    }
}
