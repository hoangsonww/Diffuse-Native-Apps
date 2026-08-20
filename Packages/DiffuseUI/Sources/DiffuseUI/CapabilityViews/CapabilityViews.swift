import DiffuseCore
import DiffuseModels
import SwiftUI

/// One capability and its current availability.
///
/// Note what is missing: any `switch` over specific capabilities. The row is
/// built entirely from `CapabilityMetadata`, which is why registering a new
/// collector makes it appear here with no UI work.
public struct CapabilityRow: View {
    private let status: CapabilityStatus
    private let onToggle: ((Bool) -> Void)?
    private let onRequestPermission: ((PermissionRequirement) -> Void)?

    public init(
        status: CapabilityStatus,
        onToggle: ((Bool) -> Void)? = nil,
        onRequestPermission: ((PermissionRequirement) -> Void)? = nil
    ) {
        self.status = status
        self.onToggle = onToggle
        self.onRequestPermission = onRequestPermission
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
            HStack(alignment: .top, spacing: DiffuseTheme.Spacing.medium) {
                Image(systemName: status.metadata.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(status.availability.color)
                    .frame(width: 28, height: 28)
                    .background(
                        status.availability.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.small, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DiffuseTheme.Spacing.small) {
                        Text(status.metadata.displayName)
                            .font(DiffuseTheme.Typography.rowTitle)
                        Image(systemName: status.availability.symbol)
                            .imageScale(.small)
                            .foregroundStyle(status.availability.color)
                    }
                    Text(status.metadata.summary)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DiffuseTheme.Spacing.small)

                if let onToggle {
                    Toggle("", isOn: Binding(get: { status.isEnabled }, set: onToggle))
                        .labelsHidden()
                        .accessibilityLabel("Collect \(status.metadata.displayName)")
                }
            }

            if let detail = status.availability.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(status.availability.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DiffuseTheme.Spacing.small) {
                Pill(
                    status.metadata.privacy.displayName,
                    symbol: status.metadata.privacy.symbol,
                    tint: status.metadata.privacy.color
                )
                Pill(status.metadata.cost.displayName, symbol: "timer")
                Pill(status.metadata.category.displayName, symbol: status.metadata.category.symbol)
            }

            if case let .permissionRequired(requirement) = status.availability, let onRequestPermission {
                Button {
                    onRequestPermission(requirement)
                } label: {
                    Label("Open \(requirement.displayName)", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, DiffuseTheme.Spacing.tight)
            }
        }
        .padding(.vertical, DiffuseTheme.Spacing.small)
    }
}

/// The capability list, grouped by category and with unsupported capabilities
/// filtered out by the catalog before it ever reaches here.
public struct CapabilityListView: View {
    private let statuses: [CapabilityStatus]
    private let onToggle: ((CapabilityID, Bool) -> Void)?
    private let onRequestPermission: ((PermissionRequirement) -> Void)?

    public init(
        statuses: [CapabilityStatus],
        onToggle: ((CapabilityID, Bool) -> Void)? = nil,
        onRequestPermission: ((PermissionRequirement) -> Void)? = nil
    ) {
        self.statuses = statuses
        self.onToggle = onToggle
        self.onRequestPermission = onRequestPermission
    }

    private var grouped: [(category: SectionCategory, statuses: [CapabilityStatus])] {
        Dictionary(grouping: statuses, by: \.metadata.category)
            .map { (category: $0.key, statuses: $0.value.sorted { $0.metadata.displayName < $1.metadata.displayName }) }
            .sorted { $0.category < $1.category }
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
            ForEach(grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    SectionHeaderLabel(
                        title: group.category.displayName,
                        symbol: group.category.symbol,
                        subtitle: availabilitySummary(group.statuses)
                    )
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(group.statuses.enumerated()), id: \.element.id) { index, status in
                                if index > 0 {
                                    Divider()
                                }
                                CapabilityRow(
                                    status: status,
                                    onToggle: onToggle.map { toggle in { toggle(status.id, $0) } },
                                    onRequestPermission: onRequestPermission
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func availabilitySummary(_ statuses: [CapabilityStatus]) -> String {
        let available = statuses.count { $0.availability.isAvailable }
        return "\(available) of \(statuses.count) available"
    }
}

/// The generated privacy disclosure.
///
/// Built from live capability metadata, so it cannot drift out of date the way
/// a hand-maintained privacy page always eventually does.
public struct PrivacyLedgerView: View {
    private let ledger: PrivacyLedger

    public init(ledger: PrivacyLedger) {
        self.ledger = ledger
    }

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: DiffuseTheme.Spacing.large) {
            Card {
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                    Label("Everything stays on this device", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(DiffuseTheme.Palette.added)
                    Text("Diffuse has no account, no server and no analytics. Snapshots are written to this "
                        + "device's storage and go nowhere else unless you export them yourself.")
                        .font(.callout)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                SectionHeaderLabel(
                    title: "Never collected",
                    symbol: "hand.raised.fill",
                    subtitle: "Diffuse does not read any of this, on any platform.",
                    tint: DiffuseTheme.Palette.critical
                )
                Card(padding: DiffuseTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                        ForEach(PrivacyLedger.neverCollected, id: \.self) { item in
                            Label(item, systemImage: "xmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(DiffuseTheme.Palette.critical, DiffuseTheme.Palette.subtleText)
                        }
                    }
                }
            }

            ForEach(ledger.groupedByClassification, id: \.classification) { group in
                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                    SectionHeaderLabel(
                        title: group.classification.displayName,
                        symbol: group.classification.symbol,
                        subtitle: group.classification.summary,
                        tint: group.classification.color
                    )
                    Card(padding: DiffuseTheme.Spacing.medium) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    Divider().padding(.vertical, DiffuseTheme.Spacing.small)
                                }
                                VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
                                    HStack(spacing: DiffuseTheme.Spacing.small) {
                                        Image(systemName: entry.symbol)
                                            .imageScale(.small)
                                            .foregroundStyle(entry.privacy.color)
                                        Text(entry.displayName)
                                            .font(DiffuseTheme.Typography.rowTitle)
                                        if !entry.isEnabled {
                                            Pill("Off", symbol: "moon.zzz")
                                        }
                                    }
                                    Text(entry.collectionDescription)
                                        .font(.caption)
                                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
