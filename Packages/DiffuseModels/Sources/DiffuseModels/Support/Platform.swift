import Foundation

/// The Apple platform a snapshot was captured on.
///
/// A value type rather than an enum so that snapshots produced by a future
/// platform can still be decoded, inspected and diffed by an older build.
public struct Platform: RawRepresentable, Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: Platform, rhs: Platform) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let macOS = Platform("macOS")
    public static let iOS = Platform("iOS")
    public static let iPadOS = Platform("iPadOS")
    public static let watchOS = Platform("watchOS")
    public static let tvOS = Platform("tvOS")
    public static let visionOS = Platform("visionOS")

    public static let all: [Platform] = [.macOS, .iOS, .iPadOS, .watchOS, .tvOS, .visionOS]

    public var displayName: String {
        rawValue
    }

    public var symbol: String {
        switch self {
        case .macOS: "macbook"
        case .iOS: "iphone"
        case .iPadOS: "ipad"
        case .watchOS: "applewatch"
        case .tvOS: "appletv"
        case .visionOS: "visionpro"
        default: "questionmark.square.dashed"
        }
    }

    /// The platform this process is running on.
    ///
    /// iPadOS is reported distinctly from iOS because the two apps expose
    /// different capability sets even though they share an SDK.
    public static var current: Platform {
        #if os(macOS)
        return .macOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(visionOS)
        return .visionOS
        #elseif os(iOS)
        #if targetEnvironment(macCatalyst)
        return .macOS
        #else
        // The iPad app reports iPadOS rather than iOS: the two share an
        // SDK but expose different capability sets, and a snapshot
        // should say which one it came from.
        if let override = ProcessInfo.processInfo.environment["DIFFUSE_PLATFORM_OVERRIDE"] {
            return Platform(rawValue: override)
        }
        return .iOS
        #endif
        #else
        return Platform("unknown")
        #endif
    }
}

extension Platform: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
