import DiffuseModels
import SwiftUI

/// A before → after value pair.
///
/// The single most-repeated element in the product, so it carries the weight of
/// the visual language: monospaced values, a direction arrow that reflects
/// whether the value went up or down, and colour drawn only from the change
/// kind.
public struct PropertyChangeView: View {
    private let change: PropertyChange
    private let kind: ChangeKind
    private let isCompact: Bool

    public init(_ change: PropertyChange, kind: ChangeKind = .modified, isCompact: Bool = false) {
        self.change = change
        self.kind = kind
        self.isCompact = isCompact
    }

    public var body: some View {
        HStack(spacing: DiffuseTheme.Spacing.small) {
            value(change.before, tint: DiffuseTheme.Palette.removed, strikethrough: kind == .removed)
            Image(systemName: change.direction.symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
            value(change.after, tint: DiffuseTheme.Palette.added, strikethrough: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(change.displayName) changed from \(change.before.formatted()) to \(change.after.formatted())"
        )
    }

    private func value(_ property: PropertyValue, tint: Color, strikethrough: Bool) -> some View {
        Text(property.formatted(style: isCompact ? .compact : .standard))
            .font(isCompact ? DiffuseTheme.Typography.valueSmall : DiffuseTheme.Typography.value)
            .strikethrough(strikethrough)
            .padding(.horizontal, DiffuseTheme.Spacing.small)
            .padding(.vertical, 3)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.small, style: .continuous)
            )
            .foregroundStyle(tint)
            .lineLimit(isCompact ? 1 : 2)
            .truncationMode(.middle)
    }
}

/// One change, as it appears in every list on every platform.
public struct ChangeRow: View {
    private let change: Change
    private let showsSection: Bool
    private let isCompact: Bool

    public init(_ change: Change, showsSection: Bool = false, isCompact: Bool = false) {
        self.change = change
        self.showsSection = showsSection
        self.isCompact = isCompact
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DiffuseTheme.Spacing.medium) {
            SeverityDot(change.severity, size: isCompact ? 6 : 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Image(systemName: change.entity.symbol)
                        .imageScale(.small)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    Text(change.entity.displayName)
                        .font(DiffuseTheme.Typography.rowTitle)
                        .lineLimit(1)
                    if change.kind != .modified {
                        Pill(change.kind.displayName, symbol: change.kind.symbol, tint: change.kind.color)
                    }
                }

                if let property = change.property {
                    if !property.displayName.isEmpty, !isCompact {
                        Text(property.displayName)
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                    PropertyChangeView(property, kind: change.kind, isCompact: isCompact)
                } else if let detail = change.detail, !isCompact {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .lineLimit(2)
                }

                if showsSection || change.confidence < 1 {
                    HStack(spacing: DiffuseTheme.Spacing.small) {
                        if showsSection {
                            Text(change.sectionName)
                                .font(.caption2)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        }
                        if change.confidence < 1 {
                            // Surfaced rather than hidden: a tolerance-based
                            // comparison that only just tripped is exactly the
                            // kind of thing a user should be able to discount.
                            Pill(
                                "\(Int(change.confidence * 100))% confidence",
                                symbol: "questionmark.circle",
                                tint: DiffuseTheme.Palette.notable
                            )
                        }
                    }
                }
            }
        }
        .padding(.vertical, isCompact ? 2 : DiffuseTheme.Spacing.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.severity.displayName): \(change.summary)")
    }
}

/// Changes grouped by their capability section.
public struct ChangeListView: View {
    private let sections: [SectionDiff]
    private let minimumSeverity: ChangeSeverity
    private let onSelect: ((Change) -> Void)?

    public init(
        sections: [SectionDiff],
        minimumSeverity: ChangeSeverity = .informational,
        onSelect: ((Change) -> Void)? = nil
    ) {
        self.sections = sections
        self.minimumSeverity = minimumSeverity
        self.onSelect = onSelect
    }

    private var visibleSections: [SectionDiff] {
        sections.compactMap { section in
            let changes = section.changes.filtered(minimumSeverity: minimumSeverity)
            guard !changes.isEmpty else { return nil }
            return SectionDiff(
                capability: section.capability,
                displayName: section.displayName,
                category: section.category,
                symbol: section.symbol,
                baseStatus: section.baseStatus,
                targetStatus: section.targetStatus,
                changes: changes,
                unchangedEntityCount: section.unchangedEntityCount
            )
        }
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
            ForEach(visibleSections) { section in
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    SectionHeaderLabel(
                        title: section.displayName,
                        symbol: section.symbol,
                        subtitle: subtitle(for: section),
                        tint: (section.peakSeverity ?? .informational).color
                    ) {
                        Text("\(section.changes.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }

                    Card(padding: DiffuseTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(section.changes.enumerated()), id: \.element.id) { index, change in
                                if index > 0 {
                                    Divider().padding(.vertical, DiffuseTheme.Spacing.small)
                                }
                                rowContent(change)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ change: Change) -> some View {
        if let onSelect {
            Button { onSelect(change) } label: {
                ChangeRow(change)
            }
            .buttonStyle(.plain)
        } else {
            ChangeRow(change)
        }
    }

    private func subtitle(for section: SectionDiff) -> String? {
        if let reason = section.incomparableReason {
            return reason
        }
        guard section.unchangedEntityCount > 0 else { return nil }
        return "\(section.unchangedEntityCount) unchanged"
    }
}

/// A temporal cluster: several changes that happened close together.
public struct ChangeClusterCard: View {
    private let cluster: ChangeCluster
    private let changes: [Change]

    public init(cluster: ChangeCluster, changes: [Change]) {
        self.cluster = cluster
        self.changes = changes
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(cluster.peakSeverity.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cluster.headline)
                            .font(.subheadline.weight(.semibold))
                        Text(window)
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                    Spacer()
                    SeverityBadge(cluster.peakSeverity)
                }

                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    ForEach(changes.prefix(5)) { change in
                        ChangeRow(change, showsSection: true, isCompact: true)
                    }
                    if changes.count > 5 {
                        Text("+ \(changes.count - 5) more in this cluster")
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                }
            }
        }
    }

    private var window: String {
        let start = cluster.start.formatted(date: .omitted, time: .shortened)
        let end = cluster.end.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start) – \(end)"
    }
}
