package com.diffuse.android.domain

object Privacy {
    private data class AliasKey(val capability: String, val identity: EntityIdentity)

    val neverCollected = listOf(
        "Passwords, tokens, and API keys",
        "Keystore private keys",
        "Environment-variable values",
        "File contents",
        "Messages, mail, photos, and browsing history",
        "Precise location",
        "Anything sent off the device",
    )

    fun redact(snapshot: Snapshot, policy: RedactionPolicy): Snapshot = redact(snapshot, policy, aliases(listOf(snapshot), policy))

    fun redactPair(base: Snapshot, target: Snapshot, policy: RedactionPolicy): Pair<Snapshot, Snapshot> {
        val aliases = aliases(listOf(base, target), policy)
        return redact(base, policy, aliases) to redact(target, policy, aliases)
    }

    private fun redact(snapshot: Snapshot, policy: RedactionPolicy, aliases: Map<AliasKey, EntityIdentity>): Snapshot {
        val sections = snapshot.sections.map { section ->
            section.copy(
                entities = section.entities.map { redactEntity(it, section.capability, section.schema, policy, aliases) },
                attributes = section.attributes.mapValues { (key, value) ->
                    val classification = section.schema.attribute(key)?.privacy ?: PrivacyClassification.LOCAL
                    if (policy.redacts(classification)) PropertyValue.string("‹redacted›") else value
                },
            )
        }
        val device = snapshot.device.copy(
            id = if (policy.redacts(PrivacyClassification.RESTRICTED)) "‹redacted›" else snapshot.device.id,
            name = if (policy.redacts(PrivacyClassification.SENSITIVE)) "‹redacted›" else snapshot.device.name,
        )
        val hidesLocalMetadata = policy.redacts(PrivacyClassification.LOCAL)
        return snapshot.copy(
            device = device,
            label = if (hidesLocalMetadata && snapshot.label != null) "‹redacted›" else snapshot.label,
            note = if (hidesLocalMetadata && snapshot.note != null) "‹redacted›" else snapshot.note,
            tags = if (hidesLocalMetadata) emptySet() else snapshot.tags,
            sections = sections,
            metadata = snapshot.metadata.copy(appliedRedaction = policy),
        )
    }

    private fun redactEntity(
        entity: SnapshotEntity,
        capability: String,
        schema: SectionSchema,
        policy: RedactionPolicy,
        aliases: Map<AliasKey, EntityIdentity>,
    ): SnapshotEntity {
        val properties = entity.properties.mapValues { (key, value) ->
            val descriptor = schema.descriptor(entity.kind, key)
            val classification = if (descriptor.privacy.rank > schema.privacy.rank) descriptor.privacy else schema.privacy
            if (policy.redacts(classification)) PropertyValue.string("‹redacted›") else value
        }
        val hideName = policy.redacts(schema.privacy) || entity.properties.keys.any { key ->
            val descriptor = schema.descriptor(entity.kind, key)
            descriptor.isPrimary && policy.redacts(if (descriptor.privacy.rank > schema.privacy.rank) descriptor.privacy else schema.privacy)
        }
        return entity.copy(
            identity = aliases[AliasKey(capability, entity.identity)] ?: entity.identity,
            displayName = if (hideName) "‹redacted›" else entity.displayName,
            subtitle = if (hideName && entity.subtitle != null) "‹redacted›" else entity.subtitle,
            properties = properties,
            children = entity.children.map { redactEntity(it, capability, schema, policy, aliases) },
            tags = if (policy.redacts(schema.privacy)) emptySet() else entity.tags,
        )
    }

    private fun aliases(snapshots: List<Snapshot>, policy: RedactionPolicy): Map<AliasKey, EntityIdentity> {
        val identities = snapshots.flatMap { snapshot ->
            snapshot.sections.filter { policy.redacts(it.schema.privacy) }.flatMap { section ->
                section.entities.flatMap { it.flattened() }.map { entity -> AliasKey(section.capability, entity.identity) }
            }
        }.distinct().sortedWith(compareBy({ it.capability }, { it.identity }))
        return identities.mapIndexed { index, key ->
            key to EntityIdentity(key.identity.kind, "redacted-${index + 1}")
        }.toMap()
    }
}
