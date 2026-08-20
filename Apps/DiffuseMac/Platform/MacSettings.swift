import DiffuseCore
import DiffuseModels
import DiffuseStorage
import DiffuseUI
import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
///
/// Preferences are the only mutable state Diffuse keeps outside the snapshot
/// library, and they are deliberately small: what to watch, how often to look,
/// and how long to keep the results. Schedule, retention and redaction live in
/// `DiffusePreferences` so iPhone and iPad honour the same keys.
@MainActor
@Observable
final class MacSettings {
    private enum Key {
        static let installIdentifier = "diffuse.installIdentifier"
        static let watchedRepositories = "diffuse.watchedRepositories"
    }

    private let defaults: UserDefaults

    let preferences: DiffusePreferences

    /// A random per-install identifier. Not a hardware serial: Diffuse only
    /// needs to know "the same install as last time".
    let installIdentifier: String

    /// A thread-safe mirror of `watchedRepositoryPaths`.
    ///
    /// The Git capability's collector runs off the main actor and needs the
    /// current list at collection time, not at registration time. Handing it a
    /// closure over main-actor state would not compile under strict
    /// concurrency, so the list is mirrored into a lock-protected box.
    let repositoryWatchList = RepositoryWatchList()

    var watchedRepositoryPaths: [String] {
        didSet {
            defaults.set(watchedRepositoryPaths, forKey: Key.watchedRepositories)
            repositoryWatchList.replace(with: watchedRepositoryPaths)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = DiffusePreferences(defaults: defaults)

        if let existing = defaults.string(forKey: Key.installIdentifier) {
            installIdentifier = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Key.installIdentifier)
            installIdentifier = generated
        }

        watchedRepositoryPaths = defaults.stringArray(forKey: Key.watchedRepositories) ?? []
        repositoryWatchList.replace(with: watchedRepositoryPaths)
    }

    var schedule: SnapshotSchedule {
        preferences.schedule
    }

    var retentionPolicy: RetentionPolicy {
        preferences.retentionPolicy
    }

    var redaction: RedactionPolicy {
        preferences.redaction
    }

    func addRepository(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        guard !watchedRepositoryPaths.contains(normalized) else { return }
        watchedRepositoryPaths.append(normalized)
    }

    func removeRepository(_ path: String) {
        watchedRepositoryPaths.removeAll { $0 == path }
    }
}

/// A small lock-protected list of watched repository paths.
///
/// Exists purely so a `@Sendable` collector closure can read a value that the
/// main actor owns, without either side reaching across isolation.
final class RepositoryWatchList: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func replace(with paths: [String]) {
        lock.lock()
        self.paths = paths
        lock.unlock()
    }

    func current() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}
