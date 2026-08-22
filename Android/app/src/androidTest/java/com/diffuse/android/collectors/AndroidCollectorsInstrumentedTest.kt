package com.diffuse.android.collectors

import androidx.test.platform.app.InstrumentationRegistry
import com.diffuse.android.domain.CollectionStatus
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class AndroidCollectorsInstrumentedTest {
    @Test
    fun everyDeviceCollectorReturnsItsDeclaredTravellingSchema() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AndroidCapabilityRegistry().collectors.forEach { collector ->
            val section = withTimeout(10_000) { collector.collect(context, "2026-08-19T12:00:00Z") }
            assertEquals(collector.metadata.id, section.capability)
            assertEquals(collector.metadata.schema, section.schema)
            assertNotEquals(CollectionStatus.FAILED, section.status)
            assertNotEquals(CollectionStatus.TIMED_OUT, section.status)
        }
    }
}
