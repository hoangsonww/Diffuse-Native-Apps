import SwiftUI

public extension View {
    /// Fills the available space with Diffuse's page colour so a scene never
    /// leaks the system black that SwiftUI uses as a default window background.
    func diffuseCanvas() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DiffuseTheme.Palette.canvas.ignoresSafeArea())
    }

    /// iOS 26 can collapse the tab bar on scroll; Diffuse's four tabs are the
    /// whole product, so they stay put.
    @ViewBuilder
    func diffuseTabBarBehavior() -> some View {
        #if os(iOS)
        // `tabBarMinimizeBehavior` only exists in the iOS 26 SDK. `#available`
        // is a *runtime* check, so the symbol still has to resolve at compile
        // time and an older Xcode fails the build. Gate on the compiler, which
        // tracks the SDK: Swift 6.2 is what ships with Xcode 26.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            self
        }
        #else
        self
        #endif
        #else
        self
        #endif
    }

    /// Paints the window itself, not just the root view, so letterboxed or
    /// windowed scenes still match the canvas. `.window` is a macOS placement.
    @ViewBuilder
    func diffuseWindowBackground() -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            containerBackground(DiffuseTheme.Palette.canvas, for: .window)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The seven-circle cluster used in the Mac sidebar, the iPhone overview and
/// the widget — the same mark as the menu bar extra.
public struct DiffuseGlyph: View {
    private let size: CGFloat

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(DiffuseTheme.Palette.ink)
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(DiffuseTheme.Palette.paper)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Wordmark plus glyph, for sidebars and empty states.
public struct DiffuseBrandMark: View {
    private let compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: DiffuseTheme.Spacing.small) {
            DiffuseGlyph(size: compact ? 22 : 28)
            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Diffuse")
                        .font(.headline)
                    Text("What changed")
                        .font(.caption2)
                        .foregroundStyle(DiffuseTheme.Palette.subtleText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diffuse")
    }
}

/// The overview headline: a Δ, a number, and a caption. Used on every
/// platform so the product reads as the same instrument.
public struct HeroMetric: View {
    private let value: Int
    private let caption: String
    private let isCompact: Bool

    public init(value: Int, caption: String, isCompact: Bool = false) {
        self.value = value
        self.caption = caption
        self.isCompact = isCompact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DiffuseTheme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline, spacing: DiffuseTheme.Spacing.small) {
                Text("Δ")
                    .font(.system(size: isCompact ? 22 : 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(DiffuseTheme.Palette.accent)
                Text("\(value)")
                    .font(
                        .system(
                            size: isCompact ? 36 : 48,
                            weight: .bold,
                            design: .rounded
                        ).monospacedDigit()
                    )
                    .contentTransition(.numericText())
                    .foregroundStyle(DiffuseTheme.Palette.ink)
                Text(value == 1 ? "change" : "changes")
                    .font(isCompact ? .headline : .title3.weight(.medium))
                    .foregroundStyle(DiffuseTheme.Palette.subtleText)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(DiffuseTheme.Palette.subtleText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(value == 1 ? "change" : "changes"). \(caption)")
    }
}
