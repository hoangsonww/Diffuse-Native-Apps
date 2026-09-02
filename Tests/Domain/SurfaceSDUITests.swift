import DiffuseSurface
import Foundation
import Testing

/// Server-driven UI is a payload from outside the binary deciding what a screen
/// shows, so the interesting tests are all about what happens when that payload
/// is wrong: absent, malformed, aimed at a newer build, or asking for something
/// this version cannot draw.
///
/// The invariant every one of these protects: **a surface can never leave a
/// screen blank or crash it.** Anything that is not renderable falls back to
/// the app's own native UI.
@Suite("Surface SDUI")
struct SurfaceSDUITests {
    // MARK: - Values

    @Test("A value round-trips through JSON for every case")
    func valueRoundTrip() throws {
        let values: [SurfaceValue] = [
            .string("text"), .int(42), .double(1.5), .bool(true),
            .list([.string("a"), .int(1), .bool(false)]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(SurfaceValue.self, from: data) == value)
        }
    }

    /// `true` decodes as `1` through a permissive number path on some
    /// platforms, which would silently turn a flag into a count.
    @Test("A boolean stays a boolean and does not decode as a number")
    func booleanIsNotANumber() throws {
        let decoded = try JSONDecoder().decode(SurfaceValue.self, from: Data("true".utf8))
        #expect(decoded == .bool(true))
        #expect(decoded.intValue == nil)
        #expect(decoded.boolValue == true)
    }

    @Test("Accessors are type-aware and numbers convert across int and double")
    func valueAccessors() {
        #expect(SurfaceValue.string("x").stringValue == "x")
        #expect(SurfaceValue.string("x").intValue == nil)
        #expect(SurfaceValue.int(3).doubleValue == 3)
        #expect(SurfaceValue.double(3.7).intValue == 3)
        #expect(SurfaceValue.list([.string("a"), .int(2)]).stringListValue == ["a"])
    }

    @Test("A value that is neither scalar nor list is rejected")
    func objectValueRejected() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SurfaceValue.self, from: Data(#"{"a":1}"#.utf8))
        }
    }

    // MARK: - Decoding

    @Test("A surface decodes from the JSON a publisher would send")
    func decodesPublishedJSON() throws {
        let json = """
        {
          "id": "help",
          "schemaVersion": 1,
          "revision": "2026-08-23a",
          "nodes": [
            { "id": "title", "type": "heading", "properties": { "text": "How to play" } },
            { "id": "steps", "type": "bullets", "properties": { "items": ["Swipe", "Merge"] } },
            { "id": "cta", "type": "button", "properties": { "title": "Start" },
              "action": { "name": "newGame", "parameters": { "confirm": true } } }
          ]
        }
        """
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))

        #expect(surface.id == "help")
        #expect(surface.nodes.count == 3)
        #expect(surface.nodes[1].properties["items"]?.stringListValue == ["Swipe", "Merge"])
        #expect(surface.nodes[2].action?.name == "newGame")
        #expect(surface.nodes[2].action?.parameters["confirm"] == .bool(true))
        #expect(surface.actionNames == ["newGame"])
    }

    /// Omitted collections are the common case in hand-authored payloads, so
    /// they must decode as empty rather than failing the whole surface.
    @Test("Absent optional fields decode as empty rather than failing")
    func absentFieldsAreTolerated() throws {
        let json = #"{ "id": "help", "nodes": [ { "id": "a", "type": "divider" } ] }"#
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))

        #expect(surface.schemaVersion == Surface.currentSchemaVersion, "an absent version means the current one")
        #expect(surface.minimumAppVersion == nil)
        #expect(surface.nodes[0].properties.isEmpty)
        #expect(surface.nodes[0].children.isEmpty)
        #expect(surface.nodes[0].action == nil)
    }

    @Test("An unknown node type parses rather than failing the payload")
    func unknownTypeParses() throws {
        let json = #"{ "id": "help", "nodes": [ { "id": "x", "type": "hologram" } ] }"#
        let surface = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))
        #expect(surface.nodes[0].type == SurfaceNodeType("hologram"))
    }

    @Test("A surface round-trips through JSON unchanged")
    func surfaceRoundTrip() throws {
        let original = Self.helpSurface
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Surface.self, from: data) == original)
    }

    // MARK: - Compatibility

    @Test("A payload built for a newer node contract is refused whole")
    func newerSchemaRefused() {
        let surface = Surface(id: "help", schemaVersion: Surface.currentSchemaVersion + 1, nodes: [Self.heading])
        let result = SurfaceValidator.compatibility(of: surface, appVersion: "1.0.0")
        #expect(result == .unsupportedSchemaVersion(found: 2, supported: 1))
    }

    @Test("A payload requiring a newer app is refused whole")
    func newerAppRefused() {
        let surface = Surface(id: "help", minimumAppVersion: "2.0.0", nodes: [Self.heading])
        #expect(SurfaceValidator.compatibility(of: surface, appVersion: "1.4.0")
            == .requiresNewerApp(minimum: "2.0.0", running: "1.4.0"))
    }

    @Test("An equal or older minimum version is accepted")
    func olderMinimumAccepted() {
        for minimum in ["1.4.0", "1.3.9", "1.0", "0.9.1"] {
            let surface = Surface(id: "help", minimumAppVersion: minimum, nodes: [Self.heading])
            #expect(SurfaceValidator.compatibility(of: surface, appVersion: "1.4.0") == nil, "\(minimum) should pass")
        }
    }

    /// `1.10.0` is newer than `1.9.0`; any string comparison says otherwise.
    @Test("Version comparison is component-wise, not lexicographic")
    func versionComparisonIsNumeric() {
        #expect(SurfaceValidator.compare("1.10.0", isNewerThan: "1.9.0"))
        #expect(!SurfaceValidator.compare("1.9.0", isNewerThan: "1.10.0"))
        #expect(!SurfaceValidator.compare("1.2.3", isNewerThan: "1.2.3"))
        #expect(SurfaceValidator.compare("2", isNewerThan: "1.9.9"))
    }

    @Test("An empty surface is treated as nothing to render")
    func emptySurfaceRefused() {
        #expect(SurfaceValidator.compatibility(of: Surface(id: "help", nodes: []), appVersion: "1.0.0") == .empty)
    }

    // MARK: - Node validation

    @Test("An unknown node type is reported and pruned, and its siblings survive")
    func unknownNodePruned() {
        let surface = Surface(id: "help", nodes: [
            Self.heading,
            SurfaceNode(id: "future", type: "hologram", properties: ["text": "?"]),
        ])
        let problems = SurfaceValidator.problems(in: surface)
        #expect(problems.count == 1)
        #expect(problems[0].kind == .unknownNodeType(SurfaceNodeType("hologram")))

        let kept = SurfaceValidator.renderable(surface.nodes)
        #expect(kept.map(\.id) == ["title"], "the known sibling still renders")
    }

    @Test("A node missing a required property is reported and pruned")
    func missingRequiredPropertyPruned() {
        let surface = Surface(id: "help", nodes: [
            SurfaceNode(id: "broken", type: .heading),
            Self.paragraph,
        ])
        let problems = SurfaceValidator.problems(in: surface)
        #expect(problems.contains { $0.nodeID == "broken" && $0.kind == .missingRequiredProperty("text") })
        #expect(SurfaceValidator.renderable(surface.nodes).map(\.id) == ["body"])
    }

    @Test("Pruning reaches into children, and a group survives losing all of them")
    func pruningIsRecursive() {
        let group = SurfaceNode(id: "g", type: .group, children: [
            Self.heading,
            SurfaceNode(id: "future", type: "hologram"),
        ])
        let kept = SurfaceValidator.renderable([group])
        #expect(kept.count == 1)
        #expect(kept[0].children.map(\.id) == ["title"])

        let emptied = SurfaceValidator.renderable([SurfaceNode(id: "g", type: .group, children: [
            SurfaceNode(id: "future", type: "hologram"),
        ])])
        #expect(emptied.count == 1, "an empty group is harmless; dropping it would be a layout surprise")
        #expect(emptied[0].children.isEmpty)
    }

    @Test("An action with no registered handler is reported")
    func unhandledActionReported() {
        let surface = Surface(id: "help", nodes: [
            SurfaceNode(id: "cta", type: .button, properties: ["title": "Go"], action: SurfaceAction(name: "launch")),
        ])
        let problems = SurfaceValidator.problems(in: surface, handledActions: ["newGame"])
        #expect(problems.contains { $0.kind == .unhandledAction("launch") })
        #expect(SurfaceValidator.problems(in: surface, handledActions: ["launch"]).isEmpty)
    }

    @Test("Duplicate node ids are reported, since a list needs stable identity")
    func duplicateIDsReported() {
        let surface = Surface(id: "help", nodes: [Self.heading, Self.heading])
        #expect(SurfaceValidator.problems(in: surface).contains { $0.kind == .duplicateNodeID("title") })
    }

    @Test("A renderer that supports fewer types prunes the rest")
    func restrictedTypeSetPrunes() {
        let surface = Surface(id: "help", nodes: [Self.heading, Self.paragraph])
        let kept = SurfaceValidator.renderable(surface.nodes, supportedTypes: [.heading])
        #expect(kept.map(\.id) == ["title"])
    }

    // MARK: - Sources

    @Test("An in-memory source returns what it holds and nil for anything else")
    func inMemorySource() async throws {
        let source = InMemorySurfaceSource([Self.helpSurface])
        #expect(try await source.surface("help")?.id == "help")
        #expect(try await source.surface("absent") == nil)
    }

    @Test("A bundled source decodes JSON and reports a missing file as nil")
    func bundledSource() async throws {
        let data = try JSONEncoder().encode(Self.helpSurface)
        let source = BundledSurfaceSource { id in id == "help" ? data : nil }
        #expect(try await source.surface("help") == Self.helpSurface)
        #expect(try await source.surface("absent") == nil)
    }

    @Test("A bundled source surfaces a decoding failure rather than hiding it")
    func bundledSourceThrowsOnGarbage() async {
        let source = BundledSurfaceSource { _ in Data("not json".utf8) }
        await #expect(throws: (any Error).self) { try await source.surface("help") }
    }

    /// The ordering *is* the policy: remote first, bundled last, so the app
    /// degrades to something that always works.
    @Test("A fallback chain takes the first hit and skips a source that throws")
    func fallbackChain() async throws {
        let broken = BundledSurfaceSource { _ in Data("not json".utf8) }
        let good = InMemorySurfaceSource([Self.helpSurface])
        let chain = FallbackSurfaceSource([broken, good])

        #expect(try await chain.surface("help")?.id == "help", "a throwing source must not break the chain")
        #expect(try await FallbackSurfaceSource([]).surface("help") == nil)
    }

    @Test("A cache serves a stored surface without asking upstream again")
    func cacheServesStored() async throws {
        let counter = CallCounter()
        let upstream = CountingSource(counter: counter, surface: Self.helpSurface)
        let clock = MutableClock(Date(timeIntervalSince1970: 0))
        let cache = CachedSurfaceSource(upstream: upstream, lifetime: 60, now: { clock.now })

        _ = try await cache.surface("help")
        _ = try await cache.surface("help")
        #expect(await counter.count == 1)

        clock.advance(by: 120)
        _ = try await cache.surface("help")
        #expect(await counter.count == 2, "past its lifetime the cache refetches")
    }

    /// Surviving an unavailable publisher is the entire reason the cache is
    /// there, so a miss upstream must not evict a good copy.
    @Test("An upstream miss does not evict a cached surface")
    func cacheSurvivesUpstreamMiss() async throws {
        let counter = CallCounter()
        let upstream = CountingSource(counter: counter, surface: Self.helpSurface, missAfterFirstCall: true)
        let cache = CachedSurfaceSource(upstream: upstream, lifetime: 0)

        #expect(try await cache.surface("help")?.id == "help")
        #expect(try await cache.surface("help")?.id == "help", "the stale copy is better than nothing")
    }

    @Test("Invalidation forces the next read to go upstream")
    func cacheInvalidation() async throws {
        let counter = CallCounter()
        let cache = CachedSurfaceSource(
            upstream: CountingSource(counter: counter, surface: Self.helpSurface),
            lifetime: 3600
        )
        _ = try await cache.surface("help")
        await cache.invalidate("help")
        _ = try await cache.surface("help")
        #expect(await counter.count == 2)
    }

    // MARK: - Resolution

    @Test("A good surface resolves to render with its nodes intact")
    func resolvesToRender() async {
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([Self.helpSurface]), appVersion: "1.0.0")
        guard case let .render(surface, problems) = await resolver.resolve("help") else {
            Issue.record("expected a render"); return
        }
        #expect(surface.nodes.count == 2)
        #expect(problems.isEmpty)
    }

    @Test("Every failure mode resolves to fallback rather than an empty screen")
    func failureModesFallBack() async {
        let cases: [(String, any SurfaceSource, SurfaceFallbackReason)] = [
            ("missing", InMemorySurfaceSource([]), .notFound),
            (
                "unreadable",
                BundledSurfaceSource { _ in Data("not json".utf8) },
                .decodingFailed("")
            ),
            (
                "too new",
                InMemorySurfaceSource([Surface(id: "help", schemaVersion: 99, nodes: [Self.heading])]),
                .incompatible(.unsupportedSchemaVersion(found: 99, supported: 1))
            ),
            (
                "all nodes unknown",
                InMemorySurfaceSource([Surface(id: "help", nodes: [SurfaceNode(id: "x", type: "hologram")])]),
                .noRenderableNodes
            ),
        ]

        for (label, source, expected) in cases {
            let resolver = SurfaceResolver(source: source, appVersion: "1.0.0")
            guard case let .fallback(reason) = await resolver.resolve("help") else {
                Issue.record("\(label): expected a fallback"); continue
            }
            switch (reason, expected) {
            case (.notFound, .notFound), (.noRenderableNodes, .noRenderableNodes),
                 (.decodingFailed, .decodingFailed):
                break
            case let (.incompatible(actual), .incompatible(want)):
                #expect(actual == want, "\(label)")
            default:
                Issue.record("\(label): got \(reason), wanted \(expected)")
            }
        }
    }

    @Test("Resolution prunes unrenderable nodes but still renders the rest")
    func resolutionPrunes() async {
        let mixed = Surface(id: "help", nodes: [
            Self.heading,
            SurfaceNode(id: "future", type: "hologram"),
            SurfaceNode(id: "broken", type: .paragraph),
        ])
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([mixed]), appVersion: "1.0.0")

        guard case let .render(surface, problems) = await resolver.resolve("help") else {
            Issue.record("expected a render"); return
        }
        #expect(surface.nodes.map(\.id) == ["title"])
        #expect(problems.count == 2, "both the unknown type and the missing property are reported")
    }

    @Test("A surface asking for an unhandled action still renders, and says so")
    func unhandledActionStillRenders() async {
        let surface = Surface(id: "help", nodes: [
            SurfaceNode(id: "cta", type: .button, properties: ["title": "Go"], action: SurfaceAction(name: "launch")),
        ])
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([surface]), appVersion: "1.0.0")

        guard case let .render(_, problems) = await resolver.resolve("help", handledActions: ["newGame"]) else {
            Issue.record("expected a render"); return
        }
        #expect(problems.contains { $0.kind == .unhandledAction("launch") })
    }

    // MARK: - Fixtures

    private static let heading = SurfaceNode(id: "title", type: .heading, properties: ["text": "How to play"])
    private static let paragraph = SurfaceNode(id: "body", type: .paragraph, properties: ["text": "Swipe to move."])

    private static let helpSurface = Surface(
        id: "help",
        revision: "test-1",
        nodes: [heading, paragraph]
    )

    private actor CallCounter {
        private(set) var count = 0
        func increment() {
            count += 1
        }
    }

    private struct CountingSource: SurfaceSource {
        let counter: CallCounter
        let surface: Surface
        var missAfterFirstCall = false

        func surface(_: SurfaceID) async throws -> Surface? {
            let previous = await counter.count
            await counter.increment()
            if missAfterFirstCall, previous > 0 {
                return nil
            }
            return surface
        }
    }

    private final class MutableClock: @unchecked Sendable {
        private var date: Date
        init(_ date: Date) {
            self.date = date
        }

        var now: Date {
            date
        }

        func advance(by interval: TimeInterval) {
            date = date.addingTimeInterval(interval)
        }
    }
}
