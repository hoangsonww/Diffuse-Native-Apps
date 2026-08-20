import DiffuseModels
import SwiftUI

/// Diffuse's visual language.
///
/// Deliberately not the SwiftUI defaults. The product is about reading
/// differences quickly, so the design leans on a restrained neutral surface
/// palette with a single accent, and reserves saturated colour exclusively for
/// severity. If everything is coloured, nothing reads as urgent.
public enum DiffuseTheme {
    // MARK: - Palette

    public enum Palette {
        /// The one non-severity accent. Blueprint indigo, not system blue and
        /// not the generic AI-product violet — Diffuse is an instrument for
        /// reading diffs, so it borrows the colour of a drawing.
        public static let accent = Color(light: 0x2F4A8A, dark: 0x8BA4E8)

        /// Near-black type in light mode, near-white in dark. Used for the
        /// numbers that matter, never for decoration.
        public static let ink = Color(light: 0x1A1C22, dark: 0xF4F1EA)

        /// The inverse of ink: the glyph cut-out, never a page colour.
        public static let paper = Color(light: 0xF3F0E8, dark: 0x12131A)

        public static let critical = Color(light: 0xC41E3A, dark: 0xFF6B7A)
        public static let significant = Color(light: 0xC45C12, dark: 0xFF9A4A)
        public static let notable = Color(light: 0x9A6B00, dark: 0xE8C15A)
        public static let informational = Color(light: 0x5E6270, dark: 0x9BA0B0)

        public static let added = Color(light: 0x176B45, dark: 0x53C08A)
        public static let removed = Color(light: 0xC41E3A, dark: 0xF57A7A)

        /// Warm paper in light mode, near-black in dark. Cold grey reads as
        /// an unstyled system app; this does not.
        public static let canvas = Color(light: 0xF3F0E8, dark: 0x0A0B0F)

        /// Cards and rows sitting on the canvas.
        public static let surface = Color(light: 0xFFFCF7, dark: 0x14151C)

        /// Nested surfaces, e.g. a property row inside a card.
        public static let surfaceRaised = Color(light: 0xEDE9DF, dark: 0x1C1D26)

        public static let hairline = Color(light: 0x1A1C22, dark: 0xF4F1EA).opacity(0.10)
        public static let subtleText = Color(light: 0x5A5E68, dark: 0x9A9DA8)
    }

    // MARK: - Metrics

    public enum Spacing {
        public static let hair: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let regular: CGFloat = 16
        public static let large: CGFloat = 24
        public static let section: CGFloat = 32
    }

    public enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 16
        public static let pill: CGFloat = 999
    }

    public enum Motion {
        /// Used for anything the user directly caused.
        public static let responsive = Animation.spring(response: 0.32, dampingFraction: 0.86)

        /// Used for content arriving asynchronously.
        public static let arrival = Animation.easeOut(duration: 0.24)
    }

    // MARK: - Typography

    public enum Typography {
        /// Numbers that sit in a column need to line up, so anything
        /// quantitative uses a monospaced digit face.
        public static let metric = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
        public static let metricLarge = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
        public static let display = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
        public static let sectionTitle = Font.system(.headline, design: .default)
        public static let rowTitle = Font.system(.body).weight(.medium)
        public static let caption = Font.system(.caption)

        /// Before/after values are compared character by character, so they get
        /// a monospaced face.
        public static let value = Font.system(.callout, design: .monospaced)
        public static let valueSmall = Font.system(.caption, design: .monospaced)
    }
}

// MARK: - Adaptive colour

public extension Color {
    /// Builds a colour that resolves differently in light and dark mode.
    ///
    /// Written by hand rather than shipped as an asset catalogue so that the
    /// palette lives in source, next to the reasoning for it, and works
    /// identically in every one of the four app targets without duplicating
    /// asset files.
    init(light: UInt32, dark: UInt32) {
        #if os(watchOS)
        // watchOS has no light appearance and no dynamic colour provider,
        // so the dark value is simply the value.
        self.init(hex: dark)
        #elseif canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #else
        self.init(hex: light)
        #endif
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Domain colours

public extension ChangeSeverity {
    var color: Color {
        switch self {
        case .critical: DiffuseTheme.Palette.critical
        case .significant: DiffuseTheme.Palette.significant
        case .notable: DiffuseTheme.Palette.notable
        case .informational: DiffuseTheme.Palette.informational
        }
    }
}

public extension ChangeKind {
    var color: Color {
        switch self {
        case .added: DiffuseTheme.Palette.added
        case .removed: DiffuseTheme.Palette.removed
        case .modified: DiffuseTheme.Palette.accent
        case .unchanged: DiffuseTheme.Palette.informational
        }
    }
}

public extension CollectionStatus {
    var color: Color {
        switch self {
        case .collected: DiffuseTheme.Palette.added
        case .partial: DiffuseTheme.Palette.notable
        case .permissionRequired: DiffuseTheme.Palette.significant
        case .timedOut, .failed: DiffuseTheme.Palette.critical
        case .unavailable, .unsupported, .skipped: DiffuseTheme.Palette.informational
        }
    }
}

public extension CapabilityAvailability {
    var color: Color {
        switch self {
        case .available: DiffuseTheme.Palette.added
        case .permissionRequired: DiffuseTheme.Palette.significant
        case .temporarilyUnavailable: DiffuseTheme.Palette.notable
        case .unavailable, .unsupported: DiffuseTheme.Palette.informational
        }
    }
}

public extension PrivacyClassification {
    var color: Color {
        switch self {
        case .public: DiffuseTheme.Palette.informational
        case .local: DiffuseTheme.Palette.accent
        case .sensitive: DiffuseTheme.Palette.significant
        case .restricted: DiffuseTheme.Palette.critical
        }
    }
}
