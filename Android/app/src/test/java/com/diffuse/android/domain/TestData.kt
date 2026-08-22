package com.diffuse.android.domain

internal const val BASE_TIME = "2026-08-19T12:00:00Z"
internal const val TARGET_TIME = "2026-08-19T12:05:00Z"

internal fun testDescriptor(
    key: String = "value",
    comparison: ComparisonRule = ComparisonRule.Exact,
    severity: ChangeSeverity = ChangeSeverity.NOTABLE,
    privacy: PrivacyClassification = PrivacyClassification.PUBLIC,
    primary: Boolean = false,
) = PropertyDescriptor(
    key = key,
    displayName = key.humanized(),
    comparison = comparison,
    severity = severity,
    privacy = privacy,
    isPrimary = primary,
)

internal fun testSchema(
    capability: String = "test.capability",
    sectionPrivacy: PrivacyClassification = PrivacyClassification.LOCAL,
    properties: List<PropertyDescriptor> = listOf(testDescriptor()),
    attributes: List<PropertyDescriptor> = emptyList(),
    additionSeverity: ChangeSeverity = ChangeSeverity.NOTABLE,
    removalSeverity: ChangeSeverity = ChangeSeverity.SIGNIFICANT,
) = SectionSchema(
    capability = capability,
    displayName = capability.humanized(),
    summary = "Observes $capability",
    category = "test",
    symbol = "science",
    privacy = sectionPrivacy,
    entityKinds = listOf(
        EntityKindDescriptor(
            kind = "item",
            singularName = "Item",
            additionSeverity = additionSeverity,
            removalSeverity = removalSeverity,
            properties = properties,
        ),
    ),
    attributes = attributes,
)

internal fun testEntity(
    id: String = "one",
    name: String = "One",
    properties: Map<String, PropertyValue> = mapOf("value" to PropertyValue.string("before")),
    children: List<SnapshotEntity> = emptyList(),
    tags: Set<String> = emptySet(),
) = SnapshotEntity(
    identity = EntityIdentity.create("item", id),
    displayName = name,
    subtitle = "Test item",
    properties = properties,
    children = children,
    tags = tags,
)

internal fun testSection(
    schema: SectionSchema = testSchema(),
    at: String = BASE_TIME,
    status: CollectionStatus = CollectionStatus.COLLECTED,
    entities: List<SnapshotEntity> = listOf(testEntity()),
    attributes: Map<String, PropertyValue> = emptyMap(),
) = SnapshotSection(
    capability = schema.capability,
    collector = "test.collector",
    collectorVersion = "1.0.0",
    collectedAt = at,
    status = status,
    schema = schema,
    entities = entities,
    attributes = attributes,
)

internal fun testSnapshot(
    id: String = "base",
    at: String = BASE_TIME,
    sections: List<SnapshotSection> = listOf(testSection()),
    label: String? = null,
    note: String? = null,
    tags: Set<String> = emptySet(),
    pinned: Boolean = false,
) = Snapshot(
    id = id,
    capturedAt = at,
    platform = "Android",
    device = DeviceIdentity("install-id", "Pixel", "Pixel 6", "Android", "14", "arm64-v8a"),
    label = label,
    note = note,
    tags = tags,
    isPinned = pinned,
    sections = sections,
)

internal fun changedSnapshot(
    before: PropertyValue = PropertyValue.string("before"),
    after: PropertyValue = PropertyValue.string("after"),
    descriptor: PropertyDescriptor = testDescriptor(),
): Pair<Snapshot, Snapshot> {
    val schema = testSchema(properties = listOf(descriptor))
    val base = testSnapshot(
        sections = listOf(
            testSection(
                schema = schema,
                entities = listOf(testEntity(properties = mapOf(descriptor.key to before))),
            ),
        ),
    )
    val target = testSnapshot(
        id = "target",
        at = TARGET_TIME,
        sections = listOf(testSection(schema = schema, at = TARGET_TIME, entities = listOf(testEntity(properties = mapOf(descriptor.key to after))))),
    )
    return base to target
}
