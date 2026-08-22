package com.diffuse.android

import android.content.pm.ActivityInfo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import com.diffuse.android.core.DiffuseService
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class MainActivityInstrumentedTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Before
    fun ensureSearchableSnapshotExists() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        runBlocking {
            DiffuseService(context).capture()
            DiffuseService(context).capture()
        }
        compose.onNodeWithContentDescription("Refresh").performClick()
        compose.onNodeWithTag("tab_snapshots").performClick()
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText("Select two snapshots to compare").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("tab_overview").performClick()
        compose.onNodeWithTag("screen_overview").assertIsDisplayed()
    }

    @After
    fun restorePortraitOrientation() {
        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    @Test
    fun primaryNavigationReachesEveryTopLevelScreen() {
        listOf(
            "snapshots" to "screen_snapshots",
            "compare" to "screen_compare",
            "settings" to "screen_settings",
            "overview" to "screen_overview",
        ).forEach { (tab, screen) ->
            compose.onNodeWithTag("tab_$tab").performClick()
            compose.onNodeWithTag(screen).assertIsDisplayed()
        }
    }

    @Test
    fun searchOpensSnapshotDetailAndReturnsToTimeline() {
        compose.onNodeWithTag("tab_snapshots").performClick()
        compose.onNodeWithTag("snapshot_search").performTextInput("Android")
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText("Open").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onAllNodesWithText("Open")[0].performClick()

        compose.onNodeWithTag("screen_snapshot_detail").assertIsDisplayed()
        compose.onNodeWithText("Snapshot name").assertIsDisplayed()
        compose.onNodeWithContentDescription("Pin").assertIsDisplayed()
        compose.onNodeWithContentDescription("Share").assertIsDisplayed()
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithText("Search snapshots and observations").assertIsDisplayed()
    }

    @Test
    fun settingsDialogsAreSafeAndSelectedTabSurvivesRotation() {
        compose.onNodeWithTag("tab_settings").performClick()
        compose.onNodeWithTag("screen_settings").performScrollToNode(hasText("Privacy ledger"))
        compose.onNodeWithText("Open").performClick()
        compose.onNodeWithText("Collected locally").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()

        compose.onNodeWithTag("screen_settings").performScrollToNode(hasText("Delete all snapshots"))
        compose.onNodeWithText("Delete all snapshots").performClick()
        compose.onNodeWithText("Delete every snapshot?").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()

        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("screen_settings").assertIsDisplayed()
    }

    @Test
    fun comparisonSummaryUsesAvailableWidthInPortraitAndLandscape() {
        compose.onNodeWithTag("tab_compare").performClick()
        if (compose.onAllNodesWithText("Compare latest two").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithText("Compare latest two").performClick()
        }
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithTag("comparison_summary").fetchSemanticsNodes().isNotEmpty()
        }

        assertComparisonSummaryFillsScreen()
        compose.onNodeWithTag("severity_chips").assertIsDisplayed()

        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithTag("comparison_summary").fetchSemanticsNodes().isNotEmpty()
        }
        assertComparisonSummaryFillsScreen()
        compose.onNodeWithTag("severity_chips").assertIsDisplayed()
    }

    private fun assertComparisonSummaryFillsScreen() {
        val screen = compose.onNodeWithTag("screen_compare").fetchSemanticsNode().boundsInRoot
        val summary = compose.onNodeWithTag("comparison_summary").fetchSemanticsNode().boundsInRoot
        val allowedInset = 40 * compose.activity.resources.displayMetrics.density
        assertTrue(
            "Comparison summary width ${summary.width} should fill screen width ${screen.width}",
            summary.width >= screen.width - allowedInset,
        )
    }
}
