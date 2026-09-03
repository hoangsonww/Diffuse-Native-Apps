import DiffuseModels
import DiffuseStorage
import SwiftUI

/// Picks the two snapshots a comparison runs over, in the place where the
/// comparison is shown.
///
/// The comparison screen used to be empty until a pair had been chosen
/// somewhere else — the timeline, on another tab — which made "Compare" a
/// destination you could only arrive at from elsewhere. Choosing what to
/// compare belongs with the comparison itself, so this view carries the whole
/// list and every app embeds it directly.
///
/// Roles are assigned by capture time, never by tap order, because
/// `DiffuseModel` always diffs oldest to newest. A control that let you swap
/// base and target would be describing something the engine does not do.
public struct SnapshotPairPicker: View {
    private let summaries: [SnapshotSummary]
    private let selection: [SnapshotID]
    private let isCompact: Bool
    private let onToggle: (SnapshotID) -> Void
    private let onCompareLatest: () -> Void
    private let onClear: () -> Void

    public init(
        summaries: [SnapshotSummary],
        selection: [SnapshotID],
        isCompact: Bool = false,
        onToggle: @escaping (SnapshotID) -> Void,
        onCompareLatest: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.summaries = summaries
        self.selection = selection
        self.isCompact = isCompact
        self.onToggle = onToggle
        self.onCompareLatest = onCompareLatest
        self.onClear = onClear
    }

    /// The selected pair in capture order, which is the order they are diffed in.
    private var ordered: [SnapshotSummary] {
        summaries
            .filter { selection.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// 1 for the base, 2 for the target — by date, matching the diff direction.
    private func role(of id: SnapshotID) -> Int? {
        guard let index = ordered.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
            slots
            list
        }
    }

    // MARK: - Slots

    private var slots: some View {
        Card(padding: DiffuseTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                HStack(alignment: .center, spacing: DiffuseTheme.Spacing.small) {
                    slot(title: "Base", summary: ordered.first, symbol: "1.circle.fill")

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .accessibilityHidden(true)

                    slot(title: "Compared with", summary: ordered.count > 1 ? ordered[1] : nil, symbol: "2.circle.fill")
                }

                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)

                    Spacer(minLength: DiffuseTheme.Spacing.small)

                    if summaries.count >= 2 {
                        Button("Latest two", action: onCompareLatest)
                            .font(.caption)
                    }
                    if !selection.isEmpty {
                        Button("Clear", action: onClear)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func slot(title: String, summary: SnapshotSummary?, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(summary == nil ? DiffuseTheme.Palette.subtleText : DiffuseTheme.Palette.accent)
                .labelStyle(.titleAndIcon)

            Text(summary.map(Self.describe) ?? "Not chosen")
                .font(.caption.weight(summary == nil ? .regular : .medium))
                .foregroundStyle(summary == nil ? DiffuseTheme.Palette.subtleText : DiffuseTheme.Palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(summary.map(Self.describe) ?? "not chosen")")
    }

    private static func describe(_ summary: SnapshotSummary) -> String {
        if let label = summary.label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        return summary.capturedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var hint: String {
        switch selection.count {
        case 0 where summaries.count < 2:
            "Diffuse needs two snapshots before it can compare anything."
        case 0:
            "Choose any two snapshots below."
        case 1:
            "Choose one more."
        default:
            "Compared oldest to newest."
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            if summaries.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No snapshots yet",
                    message: "Capture one to start building a history."
                )
                .frame(maxWidth: .infinity)
            } else {
                SnapshotTimelineView(summaries: summaries) { summary in
                    Button {
                        onToggle(summary.id)
                    } label: {
                        TimelineRow(
                            summary: summary,
                            isSelected: selection.contains(summary.id),
                            selectionOrder: role(of: summary.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(summary.id) ? [.isSelected] : [])
                    .accessibilityHint(
                        selection.contains(summary.id)
                            ? "Removes this snapshot from the comparison"
                            : "Adds this snapshot to the comparison"
                    )
                }
            }
        }
        .padding(.horizontal, isCompact ? 0 : DiffuseTheme.Spacing.small)
    }
}
