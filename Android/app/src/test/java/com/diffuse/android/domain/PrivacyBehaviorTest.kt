package com.diffuse.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivacyBehaviorTest {
    @Test
    fun noneRedactsRestrictedButLeavesLowerClassificationsVisible() {
        val properties = PrivacyClassification.entries.associate { classification ->
            classification.name.lowercase() to testDescriptor(classification.name.lowercase(), privacy = classification)
        }
        val schema = testSchema(sectionPrivacy = PrivacyClassification.PUBLIC, properties = properties.values.toList())
        val entity = testEntity(properties = properties.keys.associateWith(PropertyValue::string))
        val redacted = Privacy.redact(testSnapshot(sections = listOf(testSection(schema, entities = listOf(entity)))), RedactionPolicy.NONE)
        val values = redacted.sections.single().entities.single().properties

        assertEquals("public", values.getValue("public").text())
        assertEquals("local", values.getValue("local").text())
        assertEquals("sensitive", values.getValue("sensitive").text())
        assertEquals("‹redacted›", values.getValue("restricted").text())
    }

    @Test
    fun standardAndStrictRedactAtTheirClassificationThresholds() {
        val properties = PrivacyClassification.entries.associate { classification ->
            classification.name.lowercase() to testDescriptor(classification.name.lowercase(), privacy = classification)
        }
        val schema = testSchema(sectionPrivacy = PrivacyClassification.PUBLIC, properties = properties.values.toList())
        val source = testSnapshot(sections = listOf(testSection(schema, entities = listOf(testEntity(properties = properties.keys.associateWith(PropertyValue::string))))))

        val standard = Privacy.redact(source, RedactionPolicy.STANDARD).sections.single().entities.single().properties
        assertEquals("local", standard.getValue("local").text())
        assertEquals("‹redacted›", standard.getValue("sensitive").text())

        val strict = Privacy.redact(source, RedactionPolicy.STRICT).sections.single().entities.single().properties
        assertEquals("public", strict.getValue("public").text())
        assertEquals("‹redacted›", strict.getValue("local").text())
    }

    @Test
    fun sectionPrivacyRaisesEveryPropertyClassification() {
        val schema = testSchema(sectionPrivacy = PrivacyClassification.SENSITIVE, properties = listOf(testDescriptor(privacy = PrivacyClassification.PUBLIC)))
        val source = testSnapshot(sections = listOf(testSection(schema)))
        val redacted = Privacy.redact(source, RedactionPolicy.STANDARD)

        val entity = redacted.sections.single().entities.single()
        assertEquals("‹redacted›", entity.property("value").text())
        assertEquals("‹redacted›", entity.displayName)
        assertEquals("‹redacted›", entity.subtitle)
        assertTrue(entity.tags.isEmpty())
    }

    @Test
    fun attributesUseDescriptorPrivacyAndUnknownAttributesDefaultToLocal() {
        val schema = testSchema(
            sectionPrivacy = PrivacyClassification.PUBLIC,
            attributes = listOf(testDescriptor("publicCount", privacy = PrivacyClassification.PUBLIC), testDescriptor("secretCount", privacy = PrivacyClassification.SENSITIVE)),
        )
        val section = testSection(
            schema,
            attributes = mapOf(
                "publicCount" to PropertyValue.integer(1),
                "secretCount" to PropertyValue.integer(2),
                "futureCount" to PropertyValue.integer(3),
            ),
        )
        val redacted = Privacy.redact(testSnapshot(sections = listOf(section)), RedactionPolicy.STRICT).sections.single().attributes

        assertEquals(1.0, redacted.getValue("publicCount").number()!!, 0.0)
        assertEquals("‹redacted›", redacted.getValue("secretCount").text())
        assertEquals("‹redacted›", redacted.getValue("futureCount").text())
    }

    @Test
    fun primarySensitivePropertyHidesEntityNameWithoutHidingPublicPeers() {
        val primary = testDescriptor("serial", privacy = PrivacyClassification.SENSITIVE, primary = true)
        val visible = testDescriptor("model", privacy = PrivacyClassification.PUBLIC)
        val schema = testSchema(sectionPrivacy = PrivacyClassification.PUBLIC, properties = listOf(primary, visible))
        val entity = testEntity(properties = mapOf("serial" to PropertyValue.string("secret"), "model" to PropertyValue.string("Pixel")), tags = setOf("phone"))
        val redacted = Privacy.redact(testSnapshot(sections = listOf(testSection(schema, entities = listOf(entity)))), RedactionPolicy.STANDARD)
            .sections.single().entities.single()

        assertEquals("‹redacted›", redacted.displayName)
        assertEquals("‹redacted›", redacted.property("serial").text())
        assertEquals("Pixel", redacted.property("model").text())
        assertEquals(setOf("phone"), redacted.tags)
    }

    @Test
    fun childEntitiesAndScopedIdentitiesReceiveDistinctStableAliases() {
        val schema = testSchema(sectionPrivacy = PrivacyClassification.LOCAL)
        val child = testEntity("child")
        val parent = testEntity("parent", children = listOf(child))
        val first = testSnapshot(id = "first", sections = listOf(testSection(schema, entities = listOf(parent))))
        val second = first.copy(id = "second", capturedAt = TARGET_TIME)

        val (left, right) = Privacy.redactPair(first, second, RedactionPolicy.STRICT)
        val leftEntities = left.sections.single().entities.single().flattened()
        val rightEntities = right.sections.single().entities.single().flattened()
        assertEquals(leftEntities.map { it.identity }, rightEntities.map { it.identity })
        assertEquals(2, leftEntities.map { it.identity }.distinct().size)
        assertTrue(leftEntities.all { it.identity.value.startsWith("redacted-") })
    }

    @Test
    fun sameIdentityInDifferentCapabilitiesDoesNotShareAnAlias() {
        val firstSchema = testSchema("first", sectionPrivacy = PrivacyClassification.LOCAL)
        val secondSchema = testSchema("second", sectionPrivacy = PrivacyClassification.LOCAL)
        val source = testSnapshot(sections = listOf(testSection(firstSchema), testSection(secondSchema)))
        val redacted = Privacy.redact(source, RedactionPolicy.STRICT)

        val identities = redacted.sections.map { it.entities.single().identity }
        assertEquals(2, identities.distinct().size)
    }

    @Test
    fun strictRedactionHidesLocalMetadataAndRecordsAppliedPolicy() {
        val source = testSnapshot(label = "Before", note = "VPN issue", tags = setOf("work"))
        val redacted = Privacy.redact(source, RedactionPolicy.STRICT)

        assertEquals("‹redacted›", redacted.device.id)
        assertEquals("‹redacted›", redacted.device.name)
        assertEquals("‹redacted›", redacted.label)
        assertEquals("‹redacted›", redacted.note)
        assertTrue(redacted.tags.isEmpty())
        assertEquals(RedactionPolicy.STRICT, redacted.metadata.appliedRedaction)
        assertNotEquals(source, redacted)
    }

    @Test
    fun privacyLedgerPromisesAreNonEmptyUniqueAndExplicitlyLocalOnly() {
        assertTrue(Privacy.neverCollected.isNotEmpty())
        assertEquals(Privacy.neverCollected.size, Privacy.neverCollected.distinct().size)
        assertTrue(Privacy.neverCollected.all(String::isNotBlank))
        assertTrue(Privacy.neverCollected.any { it.contains("off the device") })
    }
}
