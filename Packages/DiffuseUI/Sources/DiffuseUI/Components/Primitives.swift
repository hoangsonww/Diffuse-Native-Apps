import DiffuseModels
import SwiftUI

// MARK: - Severity

/// A small coloured dot. The densest way to carry severity in a list row.
public struct SeverityDot: View {
    private let severity: ChangeSeverity
    private let size: CGFloat

    public init(_ severity: ChangeSeverity, size: CGFloat = 8) {
        self.severity = severity
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(severity.color)
            .frame(width: size, height: size)
            // A ring keeps the dot legible against a same-hue background and
            // gives lower severities visible weight without more colour.
            .overlay(Circle().strokeBorder(severity.color.opacity(0.28), lineWidth: size * 0.5))
            .accessibilityLabel(severity.displayName)
    }
}

/// A labelled severity chip.
public struct SeverityBadge: View {
    private let severity: ChangeSeverity
    private let count: Int?

    public init(_ severity: ChangeSeverity, count: Int? = nil) {
        self.severity = severity
        self.count = count
    }

    public var body: some View {
        HStack(spacing: DiffuseTheme.Spacing.tight) {
            SeverityDot(severity, size: 6)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            Text(severity.displayName)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, DiffuseTheme.Spacing.small)
        .padding(.vertical, DiffuseTheme.Spacing.tight)
        .background(severity.color.opacity(0.14), in: Capsule())
        .foregroundStyle(severity.color)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count.map { "\($0) \(severity.displayName)" } ?? severity.displayName)
    }
}

// MARK: - Generic chips

/// A neutral chip used for tags, statuses and counts.
public struct Pill: View {
    private let text: String
    private let symbol: String?
    private let tint: Color

    public init(_ text: String, symbol: String? = nil, tint: Color = DiffuseTheme.Palette.informational) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DiffuseTheme.Spacing.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, DiffuseTheme.Spacing.small)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Cards

/// The standard raised container.
public struct Card<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    public init(padding: CGFloat = DiffuseTheme.Spacing.regular, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DiffuseTheme.Palette.surface,
                in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DiffuseTheme.Radius.large, style: .continuous)
                    .strokeBorder(DiffuseTheme.Palette.hairline, lineWidth: 1)
            )
        #if !os(watchOS)
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
        #endif
    }
}

/// A single headline number with a caption. Used across the overview screens on
/// every platform.
public struct StatTile: View {
    private let value: String
    private let label: String
    private let symbol: String?
    private let tint: Color

    public init(value: String, label: String, symbol: String? = nil, tint: Color = DiffuseTheme.Palette.accent) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.tint = tint
    }

    public init(count: Int, label: String, symbol: String? = nil, tint: Color = DiffuseTheme.Palette.accent) {
        self.init(value: "\(count)", label: label, symbol: symbol, tint: tint)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
            HStack(spacing: DiffuseTheme.Spacing.tight) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
            Text(value)
                .font(DiffuseTheme.Typography.metric)
                .foregroundStyle(DiffuseTheme.Palette.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Section header

/// A capability or category heading with an optional trailing accessory.
public struct SectionHeaderLabel<Accessory: View>: View {
    private let title: String
    private let symbol: String
    private let subtitle: String?
    private let tint: Color
    private let accessory: Accessory

    public init(
        title: String,
        symbol: String,
        subtitle: String? = nil,
        tint: Color = DiffuseTheme.Palette.accent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.tint = tint
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: DiffuseTheme.Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.small, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DiffuseTheme.Typography.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DiffuseTheme.Spacing.small)
            accessory
        }
    }
}

public extension SectionHeaderLabel where Accessory == EmptyView {
    init(title: String, symbol: String, subtitle: String? = nil, tint: Color = DiffuseTheme.Palette.accent) {
        self.init(title: title, symbol: symbol, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

// MARK: - Empty state

/// The shared empty state. Every empty list in Diffuse says what to do next
/// rather than just reporting that there is nothing.
public struct EmptyStateView<Actions: View>: View {
    private let symbol: String
    private let title: String
    private let message: String
    private let actions: Actions

    public init(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: DiffuseTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DiffuseTheme.Palette.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(DiffuseTheme.Palette.accent)
            }
            .padding(.bottom, DiffuseTheme.Spacing.tight)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            actions
                .padding(.top, DiffuseTheme.Spacing.tight)
        }
        .frame(maxWidth: .infinity)
        .padding(DiffuseTheme.Spacing.large)
    }
}

public extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Status

/// Renders a section's collection status, including the reason it is not
/// `collected`. Used everywhere a section can be incomplete.
public struct StatusLabel: View {
    private let status: CollectionStatus
    private let detail: String?

    public init(_ status: CollectionStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DiffuseTheme.Spacing.small) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.displayName)
                    .font(.caption.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Failure

/// Surfaces a library error without covering the rest of the workspace.
public struct FailureBanner: View {
    private let message: String
    private let onDismiss: () -> Void

    public init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DiffuseTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DiffuseTheme.Palette.critical)
            Text(message)
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DiffuseTheme.Spacing.tight)
            Button("Dismiss", action: onDismiss)
                .font(.caption.weight(.semibold))
        }
        .padding(DiffuseTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DiffuseTheme.Palette.critical.opacity(0.12),
            in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.medium, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DiffuseTheme.Radius.medium, style: .continuous)
                .strokeBorder(DiffuseTheme.Palette.critical.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

public extension View {
    /// Pins a failure banner to the top of a screen so a save, import or
    /// delete error is never a silent no-op.
    func diffuseFailureBanner(_ model: DiffuseModel) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if let message = model.failureMessage {
                FailureBanner(message: message, onDismiss: model.dismissFailure)
                    .padding(.horizontal, DiffuseTheme.Spacing.regular)
                    .padding(.top, DiffuseTheme.Spacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DiffuseTheme.Motion.responsive, value: model.failureMessage)
    }
}
