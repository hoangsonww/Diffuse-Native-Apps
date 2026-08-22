package com.diffuse.android.core

import com.diffuse.android.collectors.AndroidCapabilityRegistry
import com.diffuse.android.domain.PrivacyClassification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class AndroidRegistryAndScheduleTest {
    @Test
    fun registryIsUniqueDescribedAndSchemaDriven() {
        val collectors = AndroidCapabilityRegistry().collectors
        assertEquals(collectors.size, collectors.map { it.metadata.id }.distinct().size)
        assertEquals(collectors.size, collectors.map { it.collectorID }.distinct().size)
        collectors.forEach { collector ->
            val metadata = collector.metadata
            assertEquals(metadata.id, metadata.schema.capability)
            assertTrue(metadata.id.isNotBlank())
            assertTrue(metadata.displayName.isNotBlank())
            assertTrue(metadata.summary.isNotBlank())
            assertTrue(metadata.collectionDescription.isNotBlank())
            assertTrue(metadata.schema.category.isNotBlank())
            assertTrue(metadata.schema.symbol.isNotBlank())
            metadata.schema.entityKinds.forEach { kind ->
                assertTrue(kind.kind.isNotBlank())
                assertTrue(kind.singularName.isNotBlank())
                assertEquals(kind.properties.size, kind.properties.map { it.key }.distinct().size)
                kind.properties.forEach { property ->
                    assertTrue(property.key.isNotBlank())
                    assertTrue(property.displayName.isNotBlank())
                    if (property.comparison.kind == com.diffuse.android.domain.ComparisonRule.Kind.NUMERIC ||
                        property.comparison.kind == com.diffuse.android.domain.ComparisonRule.Kind.RELATIVE
                    ) {
                        assertTrue(property.comparison.tolerance != null && property.comparison.tolerance >= 0)
                    }
                }
            }
            assertEquals(metadata.schema.attributes.size, metadata.schema.attributes.map { it.key }.distinct().size)
        }
        assertEquals(
            PrivacyClassification.SENSITIVE,
            collectors.first { it.metadata.id == "network.interfaces" }.metadata.privacy,
        )
    }

    @Test
    fun scheduleHonoursOffFirstRunAndExactCadenceBoundary() {
        val now = Instant.parse("2026-08-19T12:00:00Z")
        assertFalse(CaptureSchedule.isDue(AndroidPreferences.Cadence.OFF, null, now))
        assertTrue(CaptureSchedule.isDue(AndroidPreferences.Cadence.FOUR_HOURS, null, now))
        assertFalse(CaptureSchedule.isDue(AndroidPreferences.Cadence.FOUR_HOURS, now.minusSeconds(14_399), now))
        assertTrue(CaptureSchedule.isDue(AndroidPreferences.Cadence.FOUR_HOURS, now.minusSeconds(14_400), now))
    }

    @Test
    fun everyCadenceUsesItsExactBoundaryAndRejectsFutureCaptures() {
        val now = Instant.parse("2026-08-19T12:00:00Z")
        AndroidPreferences.Cadence.entries.filter { it.hours != null }.forEach { cadence ->
            val seconds = cadence.hours!! * 3_600
            assertFalse(CaptureSchedule.isDue(cadence, now.minusSeconds(seconds - 1), now))
            assertTrue(CaptureSchedule.isDue(cadence, now.minusSeconds(seconds), now))
            assertFalse(CaptureSchedule.isDue(cadence, now.plusSeconds(60), now))
        }
    }

    @Test
    fun registryHasExpectedAndroidCapabilitiesAndSafeDefaults() {
        val collectors = AndroidCapabilityRegistry().collectors
        assertEquals(
            setOf("device.info", "system.info", "power.battery", "display.screen", "storage.volumes", "network.path", "network.interfaces"),
            collectors.map { it.metadata.id }.toSet(),
        )
        assertTrue(collectors.all { it.metadata.enabledByDefault })
    }
}
