package com.diffuse.android.core

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import com.diffuse.android.domain.RedactionPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AndroidPreferencesInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun resetPreferences() {
        context.getSharedPreferences("diffuse.preferences", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun defaultsArePrivacyPreservingAndMatchProductPolicy() {
        val preferences = AndroidPreferences(context)
        assertEquals(AndroidPreferences.Cadence.FOUR_HOURS, preferences.cadence)
        assertTrue(preferences.skipUnchanged)
        assertEquals(90, preferences.retentionDays)
        assertEquals(1024, preferences.maximumMegabytes)
        assertEquals(RedactionPolicy.STANDARD, preferences.redaction)
        assertEquals(1_073_741_824L, preferences.retentionPolicy.maximumBytes)
    }

    @Test
    fun everyPreferenceAndCapabilityEnablementRoundTrips() {
        val preferences = AndroidPreferences(context)
        preferences.cadence = AndroidPreferences.Cadence.DAILY
        preferences.skipUnchanged = false
        preferences.retentionDays = 30
        preferences.maximumMegabytes = 256
        preferences.redaction = RedactionPolicy.STRICT
        preferences.setEnabled("device.info", false)

        val reloaded = AndroidPreferences(context)
        assertEquals(AndroidPreferences.Cadence.DAILY, reloaded.cadence)
        assertFalse(reloaded.skipUnchanged)
        assertEquals(30, reloaded.retentionDays)
        assertEquals(256, reloaded.maximumMegabytes)
        assertEquals(RedactionPolicy.STRICT, reloaded.redaction)
        assertFalse(reloaded.isEnabled("device.info", true))
        assertTrue(reloaded.isEnabled("future.capability", true))
    }

    @Test
    fun corruptEnumValuesFallBackToSafeDefaults() {
        context.getSharedPreferences("diffuse.preferences", Context.MODE_PRIVATE).edit()
            .putString("cadence", "FUTURE_CADENCE")
            .putString("redaction", "FUTURE_POLICY")
            .commit()

        val preferences = AndroidPreferences(context)
        assertEquals(AndroidPreferences.Cadence.FOUR_HOURS, preferences.cadence)
        assertEquals(RedactionPolicy.STANDARD, preferences.redaction)
    }

    @Test
    fun nonPositiveStorageLimitDisablesBytePruning() {
        val preferences = AndroidPreferences(context)
        preferences.maximumMegabytes = 0
        assertNull(preferences.retentionPolicy.maximumBytes)
        preferences.maximumMegabytes = -1
        assertNull(preferences.retentionPolicy.maximumBytes)
    }
}
