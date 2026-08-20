import Foundation

/// How sensitive a piece of collected state is.
///
/// Classification drives redaction on export rather than collection: Diffuse
/// never collects secrets in the first place, but some legitimately collected
/// values (a Wi-Fi network name, a repository path) should not leave the device
/// attached to a bug report by accident.
public enum PrivacyClassification: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    /// Safe to share anywhere, e.g. an OS version number.
    case `public`

    /// Fine to keep on device, mildly identifying if shared, e.g. a device name.
    case local

    /// Identifies the user or their environment, e.g. an SSID or repo path.
    case sensitive

    /// Never leaves the device, and is redacted from every export.
    case restricted

    public static func < (lhs: PrivacyClassification, rhs: PrivacyClassification) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .public: 0
        case .local: 1
        case .sensitive: 2
        case .restricted: 3
        }
    }

    public var displayName: String {
        switch self {
        case .public: "Public"
        case .local: "On-device"
        case .sensitive: "Sensitive"
        case .restricted: "Restricted"
        }
    }

    public var summary: String {
        switch self {
        case .public: "Contains no information that identifies you or your device."
        case .local: "Mildly identifying. Kept on device and included in exports by default."
        case .sensitive: "Identifies you or your environment. Redacted unless you opt in."
        case .restricted: "Never included in exports."
        }
    }

    public var symbol: String {
        switch self {
        case .public: "globe"
        case .local: "iphone"
        case .sensitive: "eye.slash"
        case .restricted: "lock.fill"
        }
    }
}

/// Controls how much detail leaves the device on export.
public enum RedactionPolicy: String, Sendable, Hashable, Codable, CaseIterable {
    /// Redacts nothing except `restricted` values, which are never exportable.
    case none

    /// Redacts `sensitive` and `restricted` values. The default.
    case standard

    /// Redacts everything above `public`.
    case strict

    public var displayName: String {
        switch self {
        case .none: "Full detail"
        case .standard: "Standard"
        case .strict: "Strict"
        }
    }

    public var summary: String {
        switch self {
        case .none: "Includes everything except restricted values."
        case .standard: "Redacts sensitive values such as network names and file paths."
        case .strict: "Redacts anything that could identify you or your device."
        }
    }

    /// The lowest classification that survives this policy untouched.
    public var threshold: PrivacyClassification {
        switch self {
        case .none: .restricted
        case .standard: .sensitive
        case .strict: .local
        }
    }

    public func redacts(_ classification: PrivacyClassification) -> Bool {
        classification >= threshold
    }
}
