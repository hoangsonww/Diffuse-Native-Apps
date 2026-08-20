import DiffuseModels
import Foundation

/// Supplies the identity of the device a snapshot is being taken on.
///
/// Each app provides its own: `UIDevice` on iOS, `Host`/`sysctl` on macOS.
/// Keeping it behind a protocol means the coordinator has no platform imports
/// and tests can pin the device.
public protocol DeviceIdentityProviding: Sendable {
    func deviceIdentity() -> DeviceIdentity
}

/// A cross-platform fallback built purely from `ProcessInfo`.
///
/// The install identifier is a random UUID persisted in user defaults rather
/// than a hardware serial: Diffuse needs to know "same device as last time",
/// not "which device this is".
public struct ProcessInfoDeviceIdentityProvider: DeviceIdentityProviding {
    private let installIdentifier: String
    private let deviceName: String
    private let model: String

    public init(
        installIdentifier: String,
        deviceName: String? = nil,
        model: String? = nil
    ) {
        self.installIdentifier = installIdentifier
        self.deviceName = deviceName ?? ProcessInfo.processInfo.hostName
        self.model = model ?? Self.machineIdentifier()
    }

    public func deviceIdentity() -> DeviceIdentity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceIdentity(
            id: installIdentifier,
            name: deviceName,
            model: model,
            systemName: Platform.current.rawValue,
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: Self.architecture()
        )
    }

    static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func machineIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// A device identity fixed at construction, for tests and fixtures.
public struct StaticDeviceIdentityProvider: DeviceIdentityProviding {
    private let identity: DeviceIdentity

    public init(_ identity: DeviceIdentity) {
        self.identity = identity
    }

    public func deviceIdentity() -> DeviceIdentity {
        identity
    }

    public static let testDevice = StaticDeviceIdentityProvider(
        DeviceIdentity(
            id: "test-device",
            name: "Test Mac",
            model: "Mac15,3",
            systemName: "macOS",
            systemVersion: "26.0.0",
            architecture: "arm64"
        )
    )
}
