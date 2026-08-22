import SwiftUI

/// Places compact, indivisible views from leading to trailing and moves a
/// complete view to the next line when the current line is full.
///
/// Use this for groups of `Pill` and `SeverityBadge` values. Individual chips
/// remain one line; the group adapts to Dynamic Type and narrow windows by
/// adding rows instead of compressing text inside a capsule.
public struct ChipFlowLayout: Layout {
    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat

    public init(
        horizontalSpacing: CGFloat = DiffuseTheme.Spacing.small,
        verticalSpacing: CGFloat = DiffuseTheme.Spacing.small
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) -> CGSize {
        let rows = rows(for: subviews, maximumWidth: proposal.width ?? .infinity)
        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * verticalSpacing
        return CGSize(width: proposal.width ?? contentWidth, height: contentHeight)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) {
        let rows = rows(for: subviews, maximumWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maximumWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = row.items.isEmpty ? size.width : row.width + horizontalSpacing + size.width

            if !row.items.isEmpty, proposedWidth > maximumWidth {
                rows.append(row)
                row = Row()
            }

            row.items.append(Item(subview: subview, size: size))
            row.width += (row.items.count == 1 ? 0 : horizontalSpacing) + size.width
            row.height = max(row.height, size.height)
        }

        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}
