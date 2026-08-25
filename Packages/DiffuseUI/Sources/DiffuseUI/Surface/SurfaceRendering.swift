import DiffuseSurface
import SwiftUI

/// Named intents a rendered surface is allowed to trigger.
///
/// A surface names an action; the host decides what it means. That indirection
/// is the security boundary — a payload can ask for "openSettings" but can
/// never describe how to open anything.
public struct SurfaceActionHandlers: Sendable {
    private let handlers: [String: @MainActor @Sendable (SurfaceAction) -> Void]

    public init(_ handlers: [String: @MainActor @Sendable (SurfaceAction) -> Void] = [:]) {
        self.handlers = handlers
    }

    public var names: Set<String> {
        Set(handlers.keys)
    }

    @MainActor
    public func perform(_ action: SurfaceAction) {
        handlers[action.name]?(action)
    }

    public func canHandle(_ action: SurfaceAction) -> Bool {
        handlers[action.name] != nil
    }
}

/// Renders one validated node tree using the app's own design system.
///
/// The renderer owns every visual decision. A surface supplies *content and
/// structure*; it never supplies colours, fonts, or spacing, so a published
/// payload cannot make a screen look off-brand or unreadable.
public struct SurfaceNodeView: View {
    private let node: SurfaceNode
    private let handlers: SurfaceActionHandlers

    public init(node: SurfaceNode, handlers: SurfaceActionHandlers = SurfaceActionHandlers()) {
        self.node = node
        self.handlers = handlers
    }

    public var body: some View {
        switch node.type {
        case .heading:
            Text(node.string("text") ?? "")
                .font(.headline)
                .foregroundStyle(DiffuseTheme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph:
            Text(node.string("text") ?? "")
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullets:
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.small) {
                ForEach(Array(bulletItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DiffuseTheme.Spacing.small) {
                        Text("•").foregroundStyle(DiffuseTheme.Palette.accent)
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(DiffuseTheme.Palette.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .callout:
            Text(node.string("text") ?? "")
                .font(.callout)
                .foregroundStyle(DiffuseTheme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DiffuseTheme.Spacing.medium)
                .background(
                    DiffuseTheme.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DiffuseTheme.Radius.medium, style: .continuous)
                )

        case .button:
            Button {
                if let action = node.action {
                    handlers.perform(action)
                }
            } label: {
                Text(node.string("title") ?? "")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DiffuseTheme.Palette.accent)
            // A button whose action nothing handles is shown disabled rather
            // than hidden: a dead control is confusing, a missing one is worse.
            .disabled(node.action.map { !handlers.canHandle($0) } ?? true)

        case .divider:
            Divider().overlay(DiffuseTheme.Palette.hairline)

        case .spacer:
            Spacer(minLength: CGFloat(node.properties["height"]?.doubleValue ?? 8))

        case .group:
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                ForEach(node.children) { child in
                    SurfaceNodeView(node: child, handlers: handlers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            // Unreachable for a validated tree, and deliberately empty rather
            // than a placeholder: an unknown node should leave no trace.
            EmptyView()
        }
    }

    private var bulletItems: [String] {
        node.properties["items"]?.stringListValue ?? []
    }
}

/// Renders a resolved surface, or the caller's own native content when there is
/// nothing valid to render.
///
/// Every use of this view supplies a fallback, which is what makes the whole
/// feature additive: deleting every published surface returns the apps to
/// exactly the UI they ship with.
public struct SurfaceView<Fallback: View>: View {
    private let resolution: SurfaceResolution?
    private let handlers: SurfaceActionHandlers
    private let fallback: () -> Fallback

    public init(
        resolution: SurfaceResolution?,
        handlers: SurfaceActionHandlers = SurfaceActionHandlers(),
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.resolution = resolution
        self.handlers = handlers
        self.fallback = fallback
    }

    public var body: some View {
        switch resolution {
        case let .render(surface, _):
            VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.medium) {
                ForEach(surface.nodes) { node in
                    SurfaceNodeView(node: node, handlers: handlers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .fallback, .none:
            fallback()
        }
    }
}
