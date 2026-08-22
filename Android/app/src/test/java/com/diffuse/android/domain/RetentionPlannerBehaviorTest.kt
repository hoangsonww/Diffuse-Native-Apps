package com.diffuse.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class RetentionPlannerBehaviorTest {
    private val now = Instant.parse("2026-08-20T12:00:00Z")

    @Test
    fun emptyLibraryHasNothingToDelete() {
        assertTrue(RetentionPlanner.plan(emptyList(), RetentionPolicy(), now).isEmpty())
    }

    @Test
    fun ageBoundaryIsInclusiveAndOnlyOlderSnapshotsExpire() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z"),
            summary("boundary", "2026-07-21T12:00:00Z"),
            summary("expired", "2026-07-20T11:59:59Z"),
        )
        assertEquals(listOf("expired"), RetentionPlanner.plan(summaries, RetentionPolicy(days = 30, maximumBytes = null), now))
    }

    @Test
    fun zeroDaysDisablesAgePruning() {
        val summaries = listOf(summary("new", "2026-08-20T11:00:00Z"), summary("ancient", "2020-01-01T00:00:00Z"))
        assertTrue(RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = null), now).isEmpty())
    }

    @Test
    fun protectionFlagsCanBeDisabledExplicitly() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z"),
            summary("pinned", "2020-01-01T00:00:00Z", pinned = true),
            summary("labelled", "2020-01-02T00:00:00Z", label = "Before"),
        )
        val policy = RetentionPolicy(days = 1, maximumBytes = null, protectsPinned = false, protectsLabelled = false)
        assertEquals(setOf("pinned", "labelled"), RetentionPlanner.plan(summaries, policy, now).toSet())
    }

    @Test
    fun blankLabelsDoNotProtectSnapshots() {
        val summaries = listOf(summary("new", "2026-08-20T11:00:00Z"), summary("blank", "2020-01-01T00:00:00Z", label = "   "))
        assertEquals(listOf("blank"), RetentionPlanner.plan(summaries, RetentionPolicy(days = 1, maximumBytes = null), now))
    }

    @Test
    fun negativeCountBehavesLikeZeroButNewestAlwaysSurvives() {
        val summaries = listOf(summary("new", "2026-08-20T11:00:00Z"), summary("old", "2026-08-20T10:00:00Z"))
        val deleted = RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = null, maximumCount = -10), now)
        assertEquals(listOf("old"), deleted)
        assertFalse("new" in deleted)
    }

    @Test
    fun countQuotaIgnoresProtectedSnapshots() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z"),
            summary("pinned", "2026-08-20T10:00:00Z", pinned = true),
            summary("kept", "2026-08-20T09:00:00Z"),
            summary("removed", "2026-08-20T08:00:00Z"),
        )
        assertEquals(listOf("kept", "removed"), RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = null, maximumCount = 1), now))
    }

    @Test
    fun byteQuotaAccumulatesOnlySurvivingCandidates() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z", bytes = 100),
            summary("fits", "2026-08-20T10:00:00Z", bytes = 50),
            summary("too-large", "2026-08-20T09:00:00Z", bytes = 75),
            summary("fits-after", "2026-08-20T08:00:00Z", bytes = 25),
        )
        assertEquals(listOf("too-large"), RetentionPlanner.plan(summaries, RetentionPolicy(days = 0, maximumBytes = 175), now))
    }

    @Test
    fun agePruningRunsBeforeCountAndByteQuotas() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z", bytes = 100),
            summary("recent", "2026-08-20T10:00:00Z", bytes = 100),
            summary("expired", "2020-01-01T00:00:00Z", bytes = 1_000),
        )
        val policy = RetentionPolicy(days = 30, maximumBytes = 200, maximumCount = 2)
        assertEquals(listOf("expired"), RetentionPlanner.plan(summaries, policy, now))
    }

    @Test
    fun inputOrderDoesNotChangeTheRetentionDecision() {
        val summaries = listOf(
            summary("new", "2026-08-20T11:00:00Z"),
            summary("middle", "2026-08-20T10:00:00Z"),
            summary("old", "2026-08-20T09:00:00Z"),
        )
        val policy = RetentionPolicy(days = 0, maximumBytes = null, maximumCount = 2)
        assertEquals(
            RetentionPlanner.plan(summaries, policy, now).toSet(),
            RetentionPlanner.plan(summaries.reversed(), policy, now).toSet(),
        )
    }

    private fun summary(
        id: String,
        capturedAt: String,
        pinned: Boolean = false,
        label: String? = null,
        bytes: Long = 100,
    ) = SnapshotSummary(
        id,
        capturedAt,
        "Android",
        "Pixel",
        Snapshot.Origin.MANUAL,
        label,
        pinned,
        emptySet(),
        1,
        1,
        false,
        bytes,
    )
}
