import DiffuseModels
import Foundation

/// Persists which capabilities the user has switched on.
///
/// Toggles live in the catalog, which is in-memory. Without a store they
/// reset on every launch, so turning Processes off would not actually stick.
public protocol CapabilityEnablementStoring: Sendable {
    func load() -> EnablementRecord?
    func save(_ record: EnablementRecord)
}

/// The enabled-capability set plus every ID that existed when it was saved.
///
/// `knownIDs` is what lets a later app version turn *new* default-on
/// capabilities on automatically, instead of treating "not in the saved list"
/// as "the user switched this off".
public struct EnablementRecord: Sendable, Hashable, Codable {
    public var enabledIDs: Set<CapabilityID>
    public var knownIDs: Set<CapabilityID>

    public init(enabledIDs: Set<CapabilityID>, knownIDs: Set<CapabilityID>) {
        self.enabledIDs = enabledIDs
        self.knownIDs = knownIDs
    }
}

/// `UserDefaults`-backed store used by the four apps.
public final class UserDefaultsEnablementStore: CapabilityEnablementStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "diffuse.enabledCapabilities") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> EnablementRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EnablementRecord.self, from: data)
    }

    public func save(_ record: EnablementRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}

/// In-memory store for tests.
public final class InMemoryEnablementStore: CapabilityEnablementStoring, @unchecked Sendable {
    public var record: EnablementRecord?

    public init(record: EnablementRecord? = nil) {
        self.record = record
    }

    public func load() -> EnablementRecord? {
        record
    }

    public func save(_ record: EnablementRecord) {
        self.record = record
    }
}

public extension CapabilityCatalog {
    /// Combines the registry defaults with a previously saved toggle set.
    ///
    /// Capabilities added since the last save inherit their `isEnabledByDefault`
    /// flag. Everything the user has already seen keeps the last choice.
    static func resolvedEnablement(
        registry: any CapabilityRegistry,
        stored: EnablementRecord?
    ) -> Set<CapabilityID> {
        let defaults = Set(registry.capabilities.filter(\.metadata.isEnabledByDefault).map(\.id))
        let knownNow = Set(registry.capabilities.map(\.id))
        guard let stored else { return defaults }

        let newlyAdded = knownNow.subtracting(stored.knownIDs)
        let newlyDefaultOn = newlyAdded.intersection(defaults)
        return stored.enabledIDs.intersection(knownNow).union(newlyDefaultOn)
    }
}
