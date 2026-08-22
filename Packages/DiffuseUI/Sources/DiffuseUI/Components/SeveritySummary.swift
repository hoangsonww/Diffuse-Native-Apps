import DiffuseModels
import SwiftUI

/// A single horizontal bar showing the severity mix of a diff.
///
/// Reads faster than four separate counters: the proportion of orange to grey
/// tells you whether a set of changes is worth reading before you read any of
/// it.
public struct SeveritySummaryBar: View {
    private let summary: DiffSummary
    private let height: CGFloat
    private let showsLegend: Bool

    public init(summary: DiffSummary, height: CGFloat = 10, showsLegend: Bool = true) {
        self.summary = summary
        self.height = height
        self.showsLegend = showsLegend
    }

    private var segments: [(severity: ChangeSeverity, count: Int)] {
        ChangeSeverity.allCases
            .reversed()
            .map { (severity: $0, count: summary.count($0)) }
            .filter { $0.count > 0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments, id: \.severity) { segment in
                        Capsule()
                            .fill(segment.severity.color)
                            .frame(width: width(for: segment.count, total: proxy.size.width))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(DiffuseTheme.Palette.surfaceRaised, in: Capsule())
            .animation(DiffuseTheme.Motion.responsive, value: summary)

            if showsLegend, !segments.isEmpty {
                ChipFlowLayout {
                    ForEach(segments, id: \.severity) { segment in
                        SeverityBadge(segment.severity, count: segment.count)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func width(for count: Int, total: CGFloat) -> CGFloat {
        guard summary.totalChanges > 0, total > 0 else { return 0 }
        let spacing = CGFloat(max(segments.count - 1, 0)) * 2
        let available = max(total - spacing, 0)
        let proportional = available * CGFloat(count) / CGFloat(summary.totalChanges)
        // A single critical change among two hundred informational ones must
        // still be visible, so every present severity gets a floor.
        return max(proportional, min(height, available))
    }

    private var accessibilityDescription: String {
        guard !summary.isEmpty else { return "No changes" }
        let parts = segments.map { "\($0.count) \($0.severity.displayName.lowercased())" }
        return "\(summary.headline): " + parts.joined(separator: ", ")
    }
}

/// The headline block above a comparison: both snapshots, the elapsed time and
/// the severity mix.
public struct DiffHeaderView: View {
    private let diff: DiffResult
    private let isCompact: Bool

    public init(diff: DiffResult, isCompact: Bool = false) {
        self.diff = diff
        self.isCompact = isCompact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.regular) {
            if isCompact {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    snapshotLabel(diff.base, caption: "From")
                    snapshotLabel(diff.target, caption: "To")
                }
            } else {
                HStack(alignment: .center, spacing: DiffuseTheme.Spacing.regular) {
                    snapshotLabel(diff.base, caption: "From")
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    snapshotLabel(diff.target, caption: "To")
                    Spacer(minLength: DiffuseTheme.Spacing.regular)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(diff.summary.totalChanges)")
                            .font(DiffuseTheme.Typography.metricLarge)
                            .foregroundStyle(DiffuseTheme.Palette.ink)
                            .contentTransition(.numericText())
                        Text(diff.summary.totalChanges == 1 ? "change" : "changes")
                            .font(.caption)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    }
                }
            }

            SeveritySummaryBar(summary: diff.summary)

            if diff.summary.elapsed > 0 {
                Text(elapsedDescription)
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
        }
    }

    private func snapshotLabel(_ reference: SnapshotReference, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
            Text(reference.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(reference.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
        }
    }

    private var elapsedDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        guard let span = formatter.string(from: diff.summary.elapsed) else { return "" }
        return "\(span) apart · \(diff.summary.comparedSections) sections compared"
    }
}

/// A compact severity filter, used on the comparison screens.
public struct SeverityFilterBar: View {
    @Binding private var minimumSeverity: ChangeSeverity
    private let summary: DiffSummary

    public init(minimumSeverity: Binding<ChangeSeverity>, summary: DiffSummary) {
        _minimumSeverity = minimumSeverity
        self.summary = summary
    }

    public var body: some View {
        picker
            .accessibilityLabel("Filter by severity")
    }

    /// A segmented control everywhere it exists; watchOS has no segmented
    /// style, so it falls back to the platform default.
    @ViewBuilder
    private var picker: some View {
        let content = Picker("Minimum severity", selection: $minimumSeverity) {
            ForEach(ChangeSeverity.allCases, id: \.self) { severity in
                Text(label(for: severity)).tag(severity)
            }
        }

        #if os(watchOS)
        content
        #elseif os(iOS)
        ViewThatFits(in: .horizontal) {
            content.pickerStyle(.segmented)
            content.pickerStyle(.menu)
        }
        #else
        content.pickerStyle(.segmented)
        #endif
    }

    private func label(for severity: ChangeSeverity) -> String {
        switch severity {
        case .informational: "All"
        case .notable: "Notable+"
        case .significant: "Significant+"
        case .critical: "Critical"
        }
    }
}
