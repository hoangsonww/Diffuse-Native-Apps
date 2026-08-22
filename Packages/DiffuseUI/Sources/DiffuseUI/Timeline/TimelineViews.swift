import DiffuseModels
import DiffuseStorage
import SwiftUI

/// One snapshot in the timeline.
public struct TimelineRow: View {
    private let summary: SnapshotSummary
    private let changeCount: Int?
    private let isSelected: Bool
    private let selectionOrder: Int?

    public init(
        summary: SnapshotSummary,
        changeCount: Int? = nil,
        isSelected: Bool = false,
        selectionOrder: Int? = nil
    ) {
        self.summary = summary
        self.changeCount = changeCount
        self.isSelected = isSelected
        self.selectionOrder = selectionOrder
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DiffuseTheme.Spacing.medium) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isSelected ? DiffuseTheme.Palette.accent : DiffuseTheme.Palette.surfaceRaised)
                        .frame(width: 26, height: 26)
                    if let selectionOrder {
                        Text("\(selectionOrder)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: summary.origin.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : DiffuseTheme.Palette.subtleText)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Text(summary.displayName)
                        .font(DiffuseTheme.Typography.rowTitle)
                        .foregroundStyle(isSelected ? DiffuseTheme.Palette.accent : DiffuseTheme.Palette.ink)
                        .lineLimit(1)
                    if summary.isPinned {
                        Image(systemName: "pin.fill")
                            .imageScale(.small)
                            .foregroundStyle(DiffuseTheme.Palette.notable)
                            .accessibilityLabel("Pinned")
                    }
                }

                HStack(spacing: DiffuseTheme.Spacing.small) {
                    Text(summary.capturedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    Text("·")
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    Text(summary.origin.displayName)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                }

                ChipFlowLayout {
                    if let changeCount {
                        Pill(
                            changeCount == 1 ? "1 change" : "\(changeCount) changes",
                            symbol: "arrow.triangle.2.circlepath",
                            tint: changeCount > 0 ? DiffuseTheme.Palette.accent : DiffuseTheme.Palette.informational
                        )
                    }
                    if summary.problemCount > 0 {
                        Pill(
                            "\(summary.problemCount) incomplete",
                            symbol: "exclamationmark.triangle",
                            tint: DiffuseTheme.Palette.notable
                        )
                    }
                    ForEach(summary.tags.sorted().prefix(2), id: \.self) { tag in
                        Pill(tag)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DiffuseTheme.Spacing.small)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Snapshots grouped into Today / Yesterday / date headings.
///
/// The grouping is the timeline: a flat list of timestamps is much harder to
/// scan than one broken into the days a person actually remembers.
public struct SnapshotTimelineView<Row: View>: View {
    private let summaries: [SnapshotSummary]
    private let calendar: Calendar
    private let row: (SnapshotSummary) -> Row

    public init(
        summaries: [SnapshotSummary],
        calendar: Calendar = .current,
        @ViewBuilder row: @escaping (SnapshotSummary) -> Row
    ) {
        self.summaries = summaries
        self.calendar = calendar
        self.row = row
    }

    private var groups: [(title: String, day: Date, summaries: [SnapshotSummary])] {
        Dictionary(grouping: summaries) { calendar.startOfDay(for: $0.capturedAt) }
            .map { (
                title: Self.title(for: $0.key, calendar: calendar),
                day: $0.key,
                summaries: $0.value.sorted { $0.capturedAt > $1.capturedAt }
            ) }
            .sorted { $0.day > $1.day }
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large, pinnedViews: [.sectionHeaders]) {
            ForEach(groups, id: \.day) { group in
                Section {
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(group.summaries.enumerated()), id: \.element.id) { index, summary in
                                if index > 0 {
                                    Divider()
                                }
                                row(summary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        Spacer()
                        Text("\(group.summaries.count)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                    .padding(.vertical, DiffuseTheme.Spacing.tight)
                    .background(DiffuseTheme.Palette.canvas)
                }
            }
        }
    }

    public static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        if let week = calendar.date(byAdding: .day, value: -6, to: Date()), day >= calendar.startOfDay(for: week) {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

/// A compact activity strip: how many changes happened on each recent day.
public struct ActivityStrip: View {
    private let activity: [(day: Date, count: Int)]
    private let height: CGFloat

    public init(activity: [(day: Date, count: Int)], height: CGFloat = 44) {
        self.activity = activity
        self.height = height
    }

    private var peak: Int {
        max(activity.map(\.count).max() ?? 1, 1)
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(activity, id: \.day) { entry in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(entry.count > 0 ? DiffuseTheme.Palette.accent : DiffuseTheme.Palette.surfaceRaised)
                        .frame(height: max(height * CGFloat(entry.count) / CGFloat(peak), 3))
                        .accessibilityLabel(
                            "\(entry.count) changes on \(entry.day.formatted(date: .abbreviated, time: .omitted))"
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}
