import DiffuseModels
import Foundation

/// Renders diffs and snapshots as text.
///
/// Shared by the apps' "Copy as Markdown" action and by `diffuse-dev`, so the
/// report a user pastes into a GitHub issue is the same one the CLI prints.
public enum ReportRenderer {
    // MARK: - Markdown

    public static func markdown(for diff: DiffResult, minimumSeverity: ChangeSeverity = .informational) -> String {
        var lines: [String] = []

        lines.append("# Diffuse Report")
        lines.append("")
        lines.append("**\(diff.base.displayName)** → **\(diff.target.displayName)**  ")
        lines.append("\(diff.base.platform.rawValue) · \(diff.target.deviceName)  ")
        lines.append("")
        lines.append(summaryLine(diff.summary))
        lines.append("")

        let changes = diff.changes(minimumSeverity: minimumSeverity)
        guard !changes.isEmpty else {
            lines.append("_No changes at this severity._")
            return lines.joined(separator: "\n") + "\n"
        }

        for (category, categoryChanges) in groupByCategory(changes) {
            lines.append("## \(category.displayName)")
            lines.append("")
            for change in categoryChanges {
                lines.append("- \(marker(for: change.severity)) \(escapeMarkdown(change.summary))")
                if let detail = change.detail, change.severity >= .significant {
                    lines.append("  - \(escapeMarkdown(detail))")
                }
            }
            lines.append("")
        }

        if !diff.clusters.isEmpty {
            lines.append("## Change clusters")
            lines.append("")
            for cluster in diff.clusters {
                let window = "\(timeText(cluster.start))–\(timeText(cluster.end))"
                lines
                    .append(
                        "- **\(window)** — \(cluster.headline), peak severity \(cluster.peakSeverity.displayName.lowercased())"
                    )
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("")
        lines.append("_Generated locally by Diffuse. No data left this device._")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func markdown(for snapshot: Snapshot) -> String {
        var lines: [String] = []
        lines.append("# Snapshot — \(snapshot.displayName)")
        lines.append("")
        lines.append("`\(snapshot.id.shortValue)` · \(snapshot.capturedAt.formatted(date: .long, time: .standard))  ")
        lines.append("\(snapshot.platform.rawValue) \(snapshot.device.systemVersion) · \(snapshot.device.model)  ")
        lines.append("")

        for section in snapshot.orderedSections {
            lines.append("## \(section.displayName)")
            lines.append("")
            guard section.status.hasData else {
                lines.append("_\(section.status.displayName)_")
                lines.append("")
                continue
            }

            for (key, value) in section.attributes.sorted(by: { $0.key < $1.key }) {
                let descriptor = section.schema.attributeDescriptor(for: key)
                lines
                    .append(
                        "- **\(descriptor?.displayName ?? key.rawValue.humanizedIdentifier)**: \(value.formatted())"
                    )
            }
            if !section.attributes.isEmpty {
                lines.append("")
            }

            for entity in section.sortedEntities {
                lines.append("### \(entity.displayName)")
                if let subtitle = entity.subtitle {
                    lines.append("_\(subtitle)_")
                }
                lines.append("")
                let descriptor = section.schema.descriptor(for: entity.kind)
                let ordered = descriptor?.orderedProperties.map(\.key) ?? entity.sortedPropertyKeys
                let keys = ordered + entity.sortedPropertyKeys.filter { !ordered.contains($0) }
                for key in keys {
                    let value = entity[key]
                    guard !value.isAbsent else { continue }
                    let property = section.schema.descriptor(for: key, in: entity.kind)
                    lines.append("- **\(property.displayName)**: \(value.formatted())")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Plain text

    /// The CLI rendering. Uses box characters and alignment rather than colour
    /// so it stays readable when piped to a file.
    public static func plainText(
        for diff: DiffResult,
        minimumSeverity: ChangeSeverity = .informational,
        width: Int = 64
    ) -> String {
        var lines: [String] = []
        lines.append("Diffuse Diff")
        lines.append(String(repeating: "─", count: width))
        lines.append("")
        lines.append("  \(diff.base.displayName)")
        lines.append("       ↓")
        lines.append("  \(diff.target.displayName)")
        lines.append("")

        let changes = diff.changes(minimumSeverity: minimumSeverity)
        guard !changes.isEmpty else {
            lines.append("  No changes.")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        lines.append("  \(diff.summary.headline)")
        let severityLine = ChangeSeverity.allCases.reversed()
            .compactMap { severity -> String? in
                let count = diff.summary.count(severity)
                return count > 0 ? "\(count) \(severity.displayName.lowercased())" : nil
            }
            .joined(separator: " · ")
        if !severityLine.isEmpty {
            lines.append("  \(severityLine)")
        }
        lines.append("")

        for (category, categoryChanges) in groupByCategory(changes) {
            lines.append(category.displayName.uppercased())
            for change in categoryChanges {
                lines.append("  \(glyph(for: change.severity)) \(change.summary)")
            }
            lines.append("")
        }

        if !diff.clusters.isEmpty {
            lines.append("CLUSTERS")
            for cluster in diff.clusters {
                lines.append("  \(timeText(cluster.start))–\(timeText(cluster.end))  \(cluster.headline)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Support

    private static func summaryLine(_ summary: DiffSummary) -> String {
        guard !summary.isEmpty else { return "**No changes.**" }
        let parts = ChangeSeverity.allCases.reversed().compactMap { severity -> String? in
            let count = summary.count(severity)
            return count > 0 ? "\(count) \(severity.displayName.lowercased())" : nil
        }
        return "**\(summary.headline)** — " + parts.joined(separator: ", ")
    }

    private static func groupByCategory(_ changes: [Change]) -> [(SectionCategory, [Change])] {
        Dictionary(grouping: changes, by: \.category)
            .map { ($0.key, $0.value.sortedForPresentation()) }
            .sorted { $0.0 < $1.0 }
    }

    private static func marker(for severity: ChangeSeverity) -> String {
        switch severity {
        case .critical: "🔴"
        case .significant: "🟠"
        case .notable: "🟡"
        case .informational: "⚪️"
        }
    }

    private static func glyph(for severity: ChangeSeverity) -> String {
        switch severity {
        case .critical: "!!"
        case .significant: " !"
        case .notable: " ·"
        case .informational: "  "
        }
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Escapes the characters that would otherwise turn a value like
    /// `feature/auth_v2` into unintended emphasis.
    private static func escapeMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}
