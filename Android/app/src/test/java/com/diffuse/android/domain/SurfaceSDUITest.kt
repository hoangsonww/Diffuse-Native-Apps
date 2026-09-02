package com.diffuse.android.domain

import com.diffuse.android.domain.sdui.BundledSurfaceSource
import com.diffuse.android.domain.sdui.FallbackSurfaceSource
import com.diffuse.android.domain.sdui.InMemorySurfaceSource
import com.diffuse.android.domain.sdui.Surface
import com.diffuse.android.domain.sdui.SurfaceAction
import com.diffuse.android.domain.sdui.SurfaceDecoder
import com.diffuse.android.domain.sdui.SurfaceDecodingException
import com.diffuse.android.domain.sdui.SurfaceFallbackReason
import com.diffuse.android.domain.sdui.SurfaceId
import com.diffuse.android.domain.sdui.SurfaceIncompatibility
import com.diffuse.android.domain.sdui.SurfaceNode
import com.diffuse.android.domain.sdui.SurfaceNodeType
import com.diffuse.android.domain.sdui.SurfaceProblem
import com.diffuse.android.domain.sdui.SurfaceResolution
import com.diffuse.android.domain.sdui.SurfaceResolver
import com.diffuse.android.domain.sdui.SurfaceValidator
import com.diffuse.android.domain.sdui.SurfaceValue
import org.junit.Assert.*
import org.junit.Test

/**
 * Server-driven UI means a payload from outside the binary decides what a
 * screen shows, so the interesting cases are all about that payload being
 * wrong: absent, malformed, aimed at a newer build, or asking for something
 * this version cannot draw.
 *
 * The invariant every one of these protects: **a surface can never blank a
 * screen or crash it.** Anything unrenderable falls back to the app's own UI,
 * and nothing here can reach snapshots, the diff engine, or privacy handling.
 */
class SurfaceSDUITest {
    // MARK: - Decoding

    @Test
    fun aSurfaceDecodesFromPublishedJson() {
        val surface = SurfaceDecoder.decode(
            """
            {
              "id": "help", "schemaVersion": 1, "revision": "r1",
              "nodes": [
                { "id": "t", "type": "heading", "properties": { "text": "What Diffuse does" } },
                { "id": "b", "type": "bullets", "properties": { "items": ["Capture", "Compare"] } },
                { "id": "c", "type": "button", "properties": { "title": "Take one" },
                  "action": { "name": "capture", "parameters": { "immediate": true } } }
              ]
            }
            """.trimIndent()
        )

        assertEquals(SurfaceId.HELP, surface.surfaceId)
        assertEquals(3, surface.nodes.size)
        assertEquals(listOf("Capture", "Compare"), surface.nodes[1].properties["items"]?.stringListValue)
        assertEquals(SurfaceValue.Flag(true), surface.nodes[2].action?.parameters?.get("immediate"))
        assertEquals(setOf("capture"), surface.actionNames)
    }

    /** A permissive numeric path would read `true` as `1`, turning a flag into a count. */
    @Test
    fun aBooleanStaysABooleanAndDoesNotBecomeANumber() {
        val surface = SurfaceDecoder.decode(
            """{ "id": "s", "nodes": [ { "id": "a", "type": "divider", "properties": { "flag": true } } ] }"""
        )
        val value = surface.nodes[0].properties["flag"]
        assertEquals(SurfaceValue.Flag(true), value)
        assertNull(value?.intValue)
    }

    @Test
    fun absentOptionalFieldsDecodeAsEmpty() {
        val surface = SurfaceDecoder.decode("""{ "id": "help", "nodes": [ { "id": "a", "type": "divider" } ] }""")
        assertEquals(Surface.CURRENT_SCHEMA_VERSION, surface.schemaVersion)
        assertNull(surface.minimumAppVersion)
        assertTrue(surface.nodes[0].properties.isEmpty())
        assertTrue(surface.nodes[0].children.isEmpty())
        assertNull(surface.nodes[0].action)
    }

    @Test
    fun anUnknownNodeTypeParsesRatherThanFailingThePayload() {
        val surface = SurfaceDecoder.decode("""{ "id": "help", "nodes": [ { "id": "x", "type": "hologram" } ] }""")
        assertEquals(SurfaceNodeType("hologram"), surface.nodes[0].nodeType)
    }

    /** A newer publisher adding a field must not break an older build. */
    @Test
    fun anUnknownTopLevelKeyIsIgnoredRatherThanFatal() {
        val surface = SurfaceDecoder.decode(
            """{ "id": "help", "experiment": "b", "nodes": [ { "id": "a", "type": "divider" } ] }"""
        )
        assertEquals(1, surface.nodes.size)
    }

    @Test(expected = SurfaceDecodingException::class)
    fun garbageIsRejectedRatherThanPartiallyDecoded() {
        SurfaceDecoder.decode("not json")
    }

    @Test
    fun aSurfaceRoundTripsThroughJsonUnchanged() {
        val original = helpSurface
        assertEquals(original, SurfaceDecoder.decode(SurfaceDecoder.encode(original)))
    }

    @Test
    fun everyValueShapeRoundTrips() {
        val surface = Surface(
            id = "s",
            nodes = listOf(
                SurfaceNode(
                    "a", "divider",
                    mapOf(
                        "text" to SurfaceValue.Text("x"),
                        "count" to SurfaceValue.Number(3.0),
                        "flag" to SurfaceValue.Flag(false),
                        "items" to SurfaceValue.Items(listOf(SurfaceValue.Text("one")))
                    )
                )
            )
        )
        assertEquals(surface, SurfaceDecoder.decode(SurfaceDecoder.encode(surface)))
    }

    @Test
    fun childrenDecodeAndFlattenDepthFirst() {
        val surface = SurfaceDecoder.decode(
            """
            { "id": "help", "nodes": [ { "id": "root", "type": "group", "children": [
                { "id": "a", "type": "divider" },
                { "id": "b", "type": "group", "children": [ { "id": "c", "type": "divider" } ] } ] } ] }
            """.trimIndent()
        )
        assertEquals(listOf("root", "a", "b", "c"), surface.flattenedNodes.map { it.id })
    }

    // MARK: - Value accessors

    @Test
    fun everyAccessorIsTypeAwareAcrossEveryCase() {
        val text = SurfaceValue.Text("x")
        val number = SurfaceValue.Number(3.7)
        val flag = SurfaceValue.Flag(true)
        val items = SurfaceValue.Items(listOf(SurfaceValue.Text("a"), SurfaceValue.Number(2.0)))

        assertEquals("x", text.stringValue)
        assertNull(number.stringValue)
        assertEquals(3, number.intValue)
        assertNull(text.intValue)
        assertEquals(true, flag.boolValue)
        assertNull(text.boolValue)
        assertEquals("non-text elements are skipped, not fatal", listOf("a"), items.stringListValue)
        assertNull(text.stringListValue)
    }

    @Test
    fun stringReturnsNullForAPropertyThatIsNotText() {
        val node = SurfaceNode("a", "heading", mapOf("text" to SurfaceValue.Number(1.0)))
        assertNull(node.string("text"))
        assertNull(node.string("absent"))
    }

    // MARK: - Compatibility

    @Test
    fun aPayloadBuiltForANewerContractIsRefusedWhole() {
        val surface = Surface(id = "help", schemaVersion = 99, nodes = listOf(heading))
        assertEquals(
            SurfaceIncompatibility.UnsupportedSchemaVersion(99, 1),
            SurfaceValidator.compatibility(surface, "1.0.0")
        )
    }

    @Test
    fun aPayloadRequiringANewerAppIsRefusedWhole() {
        val surface = Surface(id = "help", minimumAppVersion = "2.0.0", nodes = listOf(heading))
        assertEquals(
            SurfaceIncompatibility.RequiresNewerApp("2.0.0", "1.4.0"),
            SurfaceValidator.compatibility(surface, "1.4.0")
        )
    }

    @Test
    fun anEqualOrOlderMinimumVersionIsAccepted() {
        for (minimum in listOf("1.4.0", "1.3.9", "1.0", "0.9.1")) {
            val surface = Surface(id = "help", minimumAppVersion = minimum, nodes = listOf(heading))
            assertNull("$minimum should pass", SurfaceValidator.compatibility(surface, "1.4.0"))
        }
    }

    /** `1.10.0` is newer than `1.9.0`; any lexicographic comparison disagrees. */
    @Test
    fun versionComparisonIsComponentWiseNotLexicographic() {
        assertTrue(SurfaceValidator.isNewer("1.10.0", than = "1.9.0"))
        assertFalse(SurfaceValidator.isNewer("1.9.0", than = "1.10.0"))
        assertFalse(SurfaceValidator.isNewer("1.2.3", than = "1.2.3"))
        assertTrue(SurfaceValidator.isNewer("2", than = "1.9.9"))
    }

    @Test
    fun anEmptySurfaceIsNothingToRender() {
        assertEquals(SurfaceIncompatibility.Empty, SurfaceValidator.compatibility(Surface(id = "help"), "1.0.0"))
    }

    // MARK: - Node validation

    @Test
    fun anUnknownNodeIsPrunedAndItsSiblingsSurvive() {
        val surface = Surface(id = "help", nodes = listOf(heading, SurfaceNode("future", "hologram")))
        assertEquals(1, SurfaceValidator.problems(surface).size)
        assertEquals(listOf("title"), SurfaceValidator.renderable(surface.nodes).map { it.id })
    }

    @Test
    fun aNodeMissingARequiredPropertyIsPruned() {
        val surface = Surface(id = "help", nodes = listOf(SurfaceNode("broken", "heading"), paragraph))
        assertTrue(
            SurfaceValidator.problems(surface).any {
                it.nodeId == "broken" && it.kind == SurfaceProblem.Kind.MissingRequiredProperty("text")
            }
        )
        assertEquals(listOf("body"), SurfaceValidator.renderable(surface.nodes).map { it.id })
    }

    @Test
    fun pruningReachesIntoChildrenAndAnEmptiedParentSurvives() {
        val group = SurfaceNode("g", "group", children = listOf(heading, SurfaceNode("future", "hologram")))
        val kept = SurfaceValidator.renderable(listOf(group))
        assertEquals(1, kept.size)
        assertEquals(listOf("title"), kept[0].children.map { it.id })

        val emptied = SurfaceValidator.renderable(
            listOf(SurfaceNode("g", "group", children = listOf(SurfaceNode("x", "hologram"))))
        )
        assertEquals("an empty container is harmless; dropping it would surprise the layout", 1, emptied.size)
        assertTrue(emptied[0].children.isEmpty())
    }

    @Test
    fun duplicateNodeIdsAreReported() {
        val surface = Surface(id = "help", nodes = listOf(heading, heading))
        assertTrue(SurfaceValidator.problems(surface).any { it.kind == SurfaceProblem.Kind.DuplicateNodeId("title") })
    }

    @Test
    fun anActionWithNoHandlerIsReportedButStillRenders() {
        val surface = Surface(
            id = "help",
            nodes = listOf(
                SurfaceNode("cta", "button", mapOf("title" to SurfaceValue.Text("Go")), action = SurfaceAction("launch"))
            )
        )
        assertTrue(
            SurfaceValidator.problems(surface, handledActions = setOf("capture"))
                .any { it.kind == SurfaceProblem.Kind.UnhandledAction("launch") }
        )
        assertEquals(1, SurfaceValidator.renderable(surface.nodes).size)
    }

    @Test
    fun anEmptyHandlerSetDoesNotPoliceActions() {
        val surface = Surface(
            id = "help",
            nodes = listOf(
                SurfaceNode("cta", "button", mapOf("title" to SurfaceValue.Text("Go")), action = SurfaceAction("any"))
            )
        )
        assertTrue(SurfaceValidator.problems(surface).none { it.kind is SurfaceProblem.Kind.UnhandledAction })
    }

    @Test
    fun aRendererSupportingFewerTypesPrunesTheRest() {
        val surface = Surface(id = "help", nodes = listOf(heading, paragraph))
        assertEquals(
            listOf("title"),
            SurfaceValidator.renderable(surface.nodes, setOf(SurfaceNodeType.HEADING)).map { it.id }
        )
    }

    // MARK: - Sources

    @Test
    fun anInMemorySourceReturnsOnlyWhatItHolds() {
        val source = InMemorySurfaceSource(listOf(helpSurface))
        assertEquals(SurfaceId.HELP, source.surface(SurfaceId.HELP)?.surfaceId)
        assertNull(source.surface(SurfaceId("absent")))
    }

    @Test
    fun aBundledSourceDecodesAndReportsAMissingPayloadAsNull() {
        val source = BundledSurfaceSource { id ->
            if (id == SurfaceId.HELP) SurfaceDecoder.encode(helpSurface) else null
        }
        assertEquals(helpSurface, source.surface(SurfaceId.HELP))
        assertNull(source.surface(SurfaceId("absent")))
    }

    @Test
    fun aFallbackChainSkipsASourceThatThrows() {
        val broken = BundledSurfaceSource { "not json" }
        val chain = FallbackSurfaceSource(listOf(broken, InMemorySurfaceSource(listOf(helpSurface))))
        assertEquals(SurfaceId.HELP, chain.surface(SurfaceId.HELP)?.surfaceId)
        assertNull(FallbackSurfaceSource(emptyList()).surface(SurfaceId.HELP))
    }

    // MARK: - Resolution

    @Test
    fun aGoodSurfaceResolvesToRender() {
        val result = SurfaceResolver(InMemorySurfaceSource(listOf(helpSurface)), "1.0.0").resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Render)
        assertEquals(2, (result as SurfaceResolution.Render).surface.nodes.size)
        assertTrue(result.problems.isEmpty())
    }

    @Test
    fun everyFailureModeFallsBackRatherThanBlankingTheScreen() {
        val cases = listOf<Triple<String, SurfaceResolver, SurfaceFallbackReason>>(
            Triple(
                "missing",
                SurfaceResolver(InMemorySurfaceSource(emptyList()), "1.0.0"),
                SurfaceFallbackReason.NotFound
            ),
            Triple(
                "too new",
                SurfaceResolver(
                    InMemorySurfaceSource(listOf(Surface(id = "help", schemaVersion = 99, nodes = listOf(heading)))),
                    "1.0.0"
                ),
                SurfaceFallbackReason.Incompatible(SurfaceIncompatibility.UnsupportedSchemaVersion(99, 1))
            ),
            Triple(
                "all unknown",
                SurfaceResolver(
                    InMemorySurfaceSource(listOf(Surface(id = "help", nodes = listOf(SurfaceNode("x", "hologram"))))),
                    "1.0.0"
                ),
                SurfaceFallbackReason.NoRenderableNodes
            )
        )
        for ((label, resolver, expected) in cases) {
            val result = resolver.resolve(SurfaceId.HELP)
            assertTrue("$label: expected a fallback", result is SurfaceResolution.Fallback)
            assertEquals(label, expected, (result as SurfaceResolution.Fallback).reason)
        }
    }

    @Test
    fun anUnreadablePayloadFallsBackRatherThanThrowing() {
        val result = SurfaceResolver(BundledSurfaceSource { "not json" }, "1.0.0").resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Fallback)
        assertTrue((result as SurfaceResolution.Fallback).reason is SurfaceFallbackReason.DecodingFailed)
    }

    @Test
    fun resolutionPrunesBadNodesAndRendersTheRest() {
        val mixed = Surface(
            id = "help",
            nodes = listOf(heading, SurfaceNode("future", "hologram"), SurfaceNode("broken", "paragraph"))
        )
        val result = SurfaceResolver(InMemorySurfaceSource(listOf(mixed)), "1.0.0").resolve(SurfaceId.HELP)
        assertTrue(result is SurfaceResolution.Render)
        assertEquals(listOf("title"), (result as SurfaceResolution.Render).surface.nodes.map { it.id })
        assertEquals(2, result.problems.size)
    }

    // MARK: - Fixtures

    private val heading = SurfaceNode("title", "heading", mapOf("text" to SurfaceValue.Text("What Diffuse does")))
    private val paragraph = SurfaceNode("body", "paragraph", mapOf("text" to SurfaceValue.Text("Capture, compare.")))
    private val helpSurface = Surface(id = "help", revision = "test-1", nodes = listOf(heading, paragraph))
}
