import DiffuseModels
import SwiftUI

/// One property of an entity, rendered from its schema descriptor.
///
/// Nothing here knows what the property is. The descriptor supplies the label,
/// the unit and the privacy classification; the value supplies its own
/// formatting. That is what makes a brand new capability render correctly the
/// first time it is registered.
public struct PropertyRow: View {
    private let descriptor: PropertyDescriptor
    private let value: PropertyValue

    public init(descriptor: PropertyDescriptor, value: PropertyValue) {
        self.descriptor = descriptor
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DiffuseTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DiffuseTheme.Spacing.tight) {
                    Text(descriptor.displayName)
                        .font(.subheadline)
                    if descriptor.privacy >= .sensitive {
                        Image(systemName: descriptor.privacy.symbol)
                            .imageScale(.small)
                            .foregroundStyle(descriptor.privacy.color)
                            .accessibilityLabel(descriptor.privacy.displayName)
                    }
                }
                if let summary = descriptor.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DiffuseTheme.Spacing.small)

            valueText
                .font(DiffuseTheme.Typography.value)
                .foregroundStyle(value.isAbsent ? DiffuseTheme.Palette.subtleText : .primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// Values are selectable wherever the platform allows it, because copying
    /// a version number out of a diff is a thing people genuinely do. watchOS
    /// has no text selection at all.
    @ViewBuilder
    private var valueText: some View {
        #if os(watchOS)
        Text(displayValue)
        #else
        Text(displayValue).textSelection(.enabled)
        #endif
    }

    private var displayValue: String {
        let text = value.formatted()
        guard let suffix = descriptor.unit.suffix, !value.isAbsent else { return text }
        return "\(text) \(suffix)"
    }
}

/// One entity in a section list: name, subtitle and its primary properties.
public struct EntityRow: View {
    private let entity: SnapshotEntity
    private let descriptor: EntityKindDescriptor?

    public init(entity: SnapshotEntity, descriptor: EntityKindDescriptor?) {
        self.entity = entity
        self.descriptor = descriptor
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DiffuseTheme.Spacing.medium) {
            Image(systemName: descriptor?.symbol ?? "circle.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DiffuseTheme.Palette.accent)
                .frame(width: 24, height: 24)
                .background(
                    DiffuseTheme.Palette.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.small, style: .continuous)
                )

            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                Text(entity.displayName)
                    .font(DiffuseTheme.Typography.rowTitle)
                    .lineLimit(1)

                if let subtitle = entity.subtitle, subtitle != entity.displayName {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .lineLimit(1)
                }

                if !primaryValues.isEmpty {
                    HStack(spacing: DiffuseTheme.Spacing.small) {
                        ForEach(primaryValues, id: \.0) { label, value in
                            Pill(value, tint: DiffuseTheme.Palette.informational)
                                .accessibilityLabel("\(label) \(value)")
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DiffuseTheme.Spacing.tight)
        .contentShape(Rectangle())
    }

    private var primaryValues: [(String, String)] {
        (descriptor?.primaryProperties ?? []).compactMap { property in
            let value = entity[property.key]
            guard !value.isAbsent else { return nil }
            return (property.displayName, value.formatted(style: .compact))
        }
    }
}

/// The full detail of one entity: every property its schema declares, in
/// declared order, with anything unexpected appended rather than dropped.
public struct EntityDetailView: View {
    private let entity: SnapshotEntity
    private let schema: SectionSchema

    public init(entity: SnapshotEntity, schema: SectionSchema) {
        self.entity = entity
        self.schema = schema
    }

    private var descriptor: EntityKindDescriptor? {
        schema.descriptor(for: entity.kind)
    }

    /// Declared properties first, then anything the collector emitted that the
    /// schema does not describe. An undeclared property is a schema bug, but
    /// hiding it would make that bug invisible.
    private var orderedDescriptors: [PropertyDescriptor] {
        let declared = descriptor?.orderedProperties ?? []
        let declaredKeys = Set(declared.map(\.key))
        let extras = entity.sortedPropertyKeys
            .filter { !declaredKeys.contains($0) }
            .map { schema.descriptor(for: $0, in: entity.kind) }
        return declared + extras
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
            SectionHeaderLabel(
                title: entity.displayName,
                symbol: descriptor?.symbol ?? schema.symbol,
                subtitle: entity.subtitle ?? descriptor?.singularName
            )

            if !entity.tags.isEmpty {
                HStack(spacing: DiffuseTheme.Spacing.small) {
                    ForEach(entity.tags.sorted(), id: \.self) { tag in
                        Pill(tag, tint: DiffuseTheme.Palette.accent)
                    }
                }
            }

            Card(padding: DiffuseTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(orderedDescriptors.enumerated()), id: \.element.key) { index, property in
                        if index > 0 {
                            Divider()
                        }
                        PropertyRow(descriptor: property, value: entity[property.key])
                    }
                }
            }

            if !entity.children.isEmpty {
                Text("Contains")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                Card(padding: DiffuseTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entity.children) { child in
                            EntityRow(entity: child, descriptor: schema.descriptor(for: child.kind))
                        }
                    }
                }
            }
        }
    }
}

/// A whole section of a snapshot, rendered generically.
public struct SnapshotSectionView: View {
    private let section: SnapshotSection
    private let onSelectEntity: ((SnapshotEntity) -> Void)?

    public init(section: SnapshotSection, onSelectEntity: ((SnapshotEntity) -> Void)? = nil) {
        self.section = section
        self.onSelectEntity = onSelectEntity
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
            SectionHeaderLabel(
                title: section.displayName,
                symbol: section.symbol,
                subtitle: section.schema.summary
            ) {
                StatusLabel(section.status)
            }

            if !section.attributes.isEmpty {
                Card(padding: DiffuseTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedAttributes.enumerated()), id: \.element.0.key) { index, pair in
                            if index > 0 {
                                Divider()
                            }
                            PropertyRow(descriptor: pair.0, value: pair.1)
                        }
                    }
                }
            }

            if section.entities.isEmpty {
                Card(padding: DiffuseTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                        StatusLabel(section.status, detail: section.diagnostics.first?.message)
                        if section.status == .permissionRequired {
                            Text("Grant access to include this section in future snapshots.")
                                .font(.caption)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        }
                    }
                }
            } else {
                Card(padding: DiffuseTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(section.sortedEntities.enumerated()), id: \.element.id) { index, entity in
                            if index > 0 {
                                Divider()
                            }
                            entityRow(entity)
                        }
                    }
                }
            }

            if !section.diagnostics.isEmpty, !section.entities.isEmpty {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                    ForEach(section.diagnostics) { diagnostic in
                        Label(diagnostic.message, systemImage: diagnostic.level.symbol)
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entityRow(_ entity: SnapshotEntity) -> some View {
        let row = EntityRow(entity: entity, descriptor: section.schema.descriptor(for: entity.kind))
        if let onSelectEntity {
            Button { onSelectEntity(entity) } label: { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var sortedAttributes: [(PropertyDescriptor, PropertyValue)] {
        section.attributes
            .sorted { $0.key < $1.key }
            .map { (section.schema.attributeDescriptor(for: $0.key)
                    ?? PropertyDescriptor(key: $0.key, displayName: $0.key.rawValue.humanizedIdentifier),
                $0.value)
            }
    }
}
