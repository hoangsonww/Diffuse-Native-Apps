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
        // Wait on the pair picker rather than on timeline copy. It renders only
        // once at least two snapshots exist, which is the precondition every
        // test here depends on, and it is part of the screen under test rather
        // than an incidental string that a UI change can silently delete.
        compose.onNodeWithTag("tab_compare").performClick()
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithTag("pair_picker").fetchSemanticsNodes().isNotEmpty()
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
        if (compose.onAllNodesWithText("Latest two").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithText("Latest two").performClick()
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

    @Test
    fun comparePairIsChosenOnTheCompareScreenWithoutLeavingIt() {
        compose.onNodeWithTag("tab_compare").performClick()

        // The picker is part of this screen — no trip to the timeline first.
        compose.onNodeWithTag("pair_picker").assertIsDisplayed()

        compose.onNodeWithText("Latest two").performClick()
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithTag("comparison_summary").fetchSemanticsNodes().isNotEmpty()
        }

        // With a result on screen the picker folds away, so the comparison is not
        // pushed below the fold by the list that produced it.
        compose.onNodeWithTag("change_pair").assertIsDisplayed()

        // Reopening it and clearing returns to the picker rather than to an
        // unusable empty screen.
        compose.onNodeWithTag("change_pair").performClick()
        compose.onNodeWithTag("pair_picker").assertIsDisplayed()
        compose.onNodeWithText("Clear").performClick()
        compose.onNodeWithTag("pair_picker").assertIsDisplayed()
    }

    @Test
    fun snapshotsTabNoLongerCarriesComparisonSelection() {
        compose.onNodeWithTag("tab_snapshots").performClick()
        compose.onNodeWithTag("screen_snapshots").assertIsDisplayed()

        // Selecting a comparison belongs to the Compare screen now, so the
        // timeline must not offer it.
        assertTrue(
            "The snapshots timeline should not prompt for comparison selection",
            compose.onAllNodesWithText("Select two snapshots to compare").fetchSemanticsNodes().isEmpty(),
        )
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
