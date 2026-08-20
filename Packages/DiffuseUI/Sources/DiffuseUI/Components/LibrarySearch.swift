import DiffuseCore
import DiffuseModels
import SwiftUI

/// Hits from the library search index: snapshots, sections and entities.
public struct LibrarySearchResultsView: View {
    private let results: [SearchResult]
    private let onSelect: (SearchResult) -> Void

    public init(results: [SearchResult], onSelect: @escaping (SearchResult) -> Void) {
        self.results = results
        self.onSelect = onSelect
    }

    public var body: some View {
        if results.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "No matches",
                message: "Try a snapshot name, an app, a network, or a tool — search looks through everything that has been recorded."
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        Divider()
                    }
                    Button {
                        onSelect(result)
                    } label: {
                        SearchResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

public struct SearchResultRow: View {
    private let result: SearchResult

    public init(result: SearchResult) {
        self.result = result
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DiffuseTheme.Spacing.medium) {
            Image(systemName: result.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DiffuseTheme.Palette.accent)
                .frame(width: 28, height: 28)
                .background(
                    DiffuseTheme.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.small, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(DiffuseTheme.Typography.rowTitle)
                    .foregroundStyle(DiffuseTheme.Palette.ink)
                    .multilineTextAlignment(.leading)
                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Text(kindLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
        }
        .padding(.vertical, DiffuseTheme.Spacing.small)
        .contentShape(Rectangle())
    }

    private var kindLabel: String {
        switch result.target {
        case .snapshot: "Snapshot"
        case .section: "Section"
        case .entity: "Item"
        case .change: "Change"
        }
    }
}

public extension SearchResult {
    var snapshotID: SnapshotID? {
        switch target {
        case let .snapshot(id), let .section(id, _), let .entity(id, _, _):
            id
        case .change:
            nil
        }
    }

    var entityIdentity: EntityIdentity? {
        if case let .entity(_, _, identity) = target {
            return identity
        }
        return nil
    }
}
