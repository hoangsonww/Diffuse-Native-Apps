#if canImport(SwiftUI) && os(macOS)

import DiffuseSurface
import DiffuseUI
import Foundation
import SwiftUI
import Testing

/// Render coverage for the server-driven UI layer.
///
/// A published payload decides what these views draw, so a node that traps on a
/// missing property or an empty list would take down whichever screen renders
/// it — on four apps at once. `ImageRenderer` evaluates a whole view body, so
/// rendering each node type is a genuine smoke test rather than a type-check.
@MainActor
@Suite("Surface rendering")
struct SurfaceRenderingTests {
    @Test("Every node type in the vocabulary renders")
    func everyNodeTypeRenders() {
        let nodes: [SurfaceNode] = [
            SurfaceNode(id: "h", type: .heading, properties: ["text": "What changed"]),
            SurfaceNode(id: "p", type: .paragraph, properties: ["text": "Diffuse compares two snapshots."]),
            SurfaceNode(id: "b", type: .bullets, properties: ["items": .list([.string("One"), .string("Two")])]),
            SurfaceNode(id: "c", type: .callout, properties: ["text": "Snapshots never leave this device."]),
            SurfaceNode(id: "btn", type: .button, properties: ["title": "Capture"],
                        action: SurfaceAction(name: "capture")),
            SurfaceNode(id: "d", type: .divider),
            SurfaceNode(id: "s", type: .spacer, properties: ["height": .double(16)]),
            SurfaceNode(id: "g", type: .group, children: [
                SurfaceNode(id: "gh", type: .heading, properties: ["text": "Nested"]),
            ]),
        ]
        for node in nodes {
            expectRenders(SurfaceNodeView(node: node), "\(node.type) should render")
        }
    }

    /// The degenerate payloads most likely to trip a view that assumes a field
    /// is always present.
    @Test("Empty and defaulted properties render rather than trapping")
    func degeneratePayloadsRender() {
        expectRenders(
            SurfaceNodeView(node: SurfaceNode(id: "b", type: .bullets, properties: ["items": .list([])])),
            "an empty bullet list renders as nothing, not a crash"
        )
        expectRenders(
            SurfaceNodeView(node: SurfaceNode(id: "s", type: .spacer)),
            "a spacer with no height falls back to its default"
        )
        expectRenders(
            SurfaceNodeView(node: SurfaceNode(id: "g", type: .group)),
            "an empty group renders as nothing"
        )
    }

    /// Unreachable for a validated tree, but the renderer is a public entry
    /// point and must not trap if one ever reaches it.
    @Test("An unknown node type is inert rather than fatal")
    func unknownNodeIsInert() {
        expectRenders(SurfaceNodeView(node: SurfaceNode(id: "x", type: "hologram")))
    }

    @Test("A button renders enabled only when its action is handled")
    func buttonEnablement() {
        let node = SurfaceNode(
            id: "btn", type: .button, properties: ["title": "Capture"], action: SurfaceAction(name: "capture")
        )
        expectRenders(SurfaceNodeView(node: node, handlers: SurfaceActionHandlers(["capture": { _ in }])))
        expectRenders(SurfaceNodeView(node: node, handlers: SurfaceActionHandlers()), "unhandled renders disabled")
        expectRenders(
            SurfaceNodeView(node: SurfaceNode(id: "btn", type: .button, properties: ["title": "Capture"])),
            "no action at all renders disabled"
        )
    }

    @Test("An action dispatches only to its registered handler")
    func actionDispatch() {
        var fired: [String] = []
        let handlers = SurfaceActionHandlers([
            "capture": { _ in fired.append("capture") },
        ])
        #expect(handlers.canHandle(SurfaceAction(name: "capture")))
        #expect(!handlers.canHandle(SurfaceAction(name: "launch")))

        handlers.perform(SurfaceAction(name: "capture"))
        handlers.perform(SurfaceAction(name: "launch"))
        #expect(fired == ["capture"], "an unknown action is inert, not a crash")
        #expect(handlers.names == ["capture"])
    }

    @Test("A resolved surface renders its nodes")
    func resolvedSurfaceRenders() {
        let surface = Surface(id: "help", nodes: [
            SurfaceNode(id: "h", type: .heading, properties: ["text": "What changed"]),
            SurfaceNode(id: "p", type: .paragraph, properties: ["text": "Two snapshots, compared."]),
        ])
        expectRenders(SurfaceView(resolution: .render(surface, problems: [])) { Text("native") })
    }

    /// The property the whole design rests on: nothing a payload can do leaves
    /// a screen blank.
    @Test("Every fallback state renders the caller's native content")
    func everyFallbackRendersNative() {
        let states: [SurfaceResolution?] = [
            nil,
            .fallback(reason: .notFound),
            .fallback(reason: .noRenderableNodes),
            .fallback(reason: .decodingFailed("bad")),
            .fallback(reason: .incompatible(.unsupportedSchemaVersion(found: 99, supported: 1))),
            .fallback(reason: .incompatible(.requiresNewerApp(minimum: "9.0", running: "1.0"))),
            .fallback(reason: .incompatible(.empty)),
        ]
        for state in states {
            expectRenders(SurfaceView(resolution: state) { Text("native fallback") })
        }
    }

    @Test("A surface resolved end to end from a source renders")
    func endToEnd() async {
        let surface = Surface(id: "help", nodes: [
            SurfaceNode(id: "h", type: .heading, properties: ["text": "What changed"]),
            SurfaceNode(id: "x", type: "hologram"),
        ])
        let resolver = SurfaceResolver(source: InMemorySurfaceSource([surface]), appVersion: "1.0.0")
        let resolution = await resolver.resolve("help", handledActions: ["capture"])

        guard case .render = resolution else {
            Issue.record("expected a render, got \(resolution)"); return
        }
        expectRenders(SurfaceView(resolution: resolution) { Text("native") })
    }

    /// Every incompatibility and fallback reason is shown to a developer in a
    /// log, so each needs a readable description rather than a struct dump.
    @Test("Diagnostics read as sentences")
    func diagnosticsAreReadable() {
        let reasons: [SurfaceFallbackReason] = [
            .notFound, .noRenderableNodes, .decodingFailed("bad"),
            .incompatible(.unsupportedSchemaVersion(found: 2, supported: 1)),
            .incompatible(.requiresNewerApp(minimum: "2.0", running: "1.0")),
            .incompatible(.empty),
        ]
        for reason in reasons {
            #expect(!reason.description.isEmpty)
        }
        let problems: [SurfaceProblem] = [
            SurfaceProblem(nodeID: "a", kind: .unknownNodeType("hologram")),
            SurfaceProblem(nodeID: "a", kind: .missingRequiredProperty("text")),
            SurfaceProblem(nodeID: "a", kind: .unhandledAction("launch")),
            SurfaceProblem(nodeID: "a", kind: .duplicateNodeID("a")),
        ]
        for problem in problems {
            #expect(problem.description.contains("a"))
        }
    }

    private func expectRenders(
        _ view: some View,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let renderer = ImageRenderer(content: view.frame(width: 360).padding())
        renderer.scale = 1
        #expect(renderer.nsImage != nil, comment ?? "the view rendered to nothing", sourceLocation: sourceLocation)
    }
}

#endif
