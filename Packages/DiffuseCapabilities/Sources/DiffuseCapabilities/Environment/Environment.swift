import DiffuseModels
import Foundation

/// Supplies the current time.
///
/// Collectors and the scheduler take a time source rather than calling `Date()`
/// so that every test can pin the clock and every fixture is reproducible.
public protocol TimeSource: Sendable {
    var now: Date { get }
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public var now: Date {
        Date()
    }
}

/// A clock that only moves when a test tells it to.
public final class FixedTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_755_000_000)) {
        current = start
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}

/// The filesystem operations collectors are allowed to perform.
///
/// Deliberately read-only and deliberately small: a collector that needs more
/// than this is probably collecting too much.
public protocol FileSystemProviding: Sendable {
    func fileExists(at path: String) -> Bool
    func isDirectory(at path: String) -> Bool
    func contentsOfDirectory(at path: String) throws -> [String]
    func readFile(at path: String, maximumBytes: Int) throws -> Data
    func attributes(at path: String) throws -> FileAttributes
    var homeDirectory: String { get }
}

public struct FileAttributes: Sendable, Hashable {
    public let size: Int64
    public let modifiedAt: Date
    public let isDirectory: Bool
    public let isSymbolicLink: Bool

    public init(size: Int64, modifiedAt: Date, isDirectory: Bool, isSymbolicLink: Bool) {
        self.size = size
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
    }
}

public struct SystemFileSystem: FileSystemProviding {
    public init() {}

    public func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func contentsOfDirectory(at path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path).sorted()
    }

    /// Reads at most `maximumBytes`. Collectors never need whole files, and
    /// capping the read is a cheap guard against a pathological input.
    public func readFile(at path: String, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumBytes) ?? Data()
    }

    public func attributes(at path: String) throws -> FileAttributes {
        let values = try FileManager.default.attributesOfItem(atPath: path)
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return FileAttributes(
            size: (values[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedAt: values[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0),
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: (values[.type] as? FileAttributeType) == .typeSymbolicLink
        )
    }

    public var homeDirectory: String {
        NSHomeDirectory()
    }
}

/// An in-memory filesystem for collector tests.
public struct FakeFileSystem: FileSystemProviding {
    public var files: [String: Data]
    public var directories: Set<String>
    public var homeDirectory: String

    public init(files: [String: Data] = [:], directories: Set<String> = [], homeDirectory: String = "/Users/test") {
        self.files = files
        self.directories = directories
        self.homeDirectory = homeDirectory
    }

    public init(textFiles: [String: String], directories: Set<String> = [], homeDirectory: String = "/Users/test") {
        self.init(
            files: textFiles.mapValues { Data($0.utf8) },
            directories: directories,
            homeDirectory: homeDirectory
        )
    }

    public func fileExists(at path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    public func isDirectory(at path: String) -> Bool {
        directories.contains(path)
    }

    public func contentsOfDirectory(at path: String) throws -> [String] {
        guard directories.contains(path) else {
            throw CollectorError.unavailable("No such directory: \(path)")
        }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let entries = (Array(files.keys) + Array(directories))
            .filter { $0.hasPrefix(prefix) && $0 != path }
            .compactMap { $0.dropFirst(prefix.count).split(separator: "/").first.map(String.init) }
        return Array(Set(entries)).sorted()
    }

    public func readFile(at path: String, maximumBytes: Int) throws -> Data {
        guard let data = files[path] else {
            throw CollectorError.unavailable("No such file: \(path)")
        }
        return data.prefix(maximumBytes)
    }

    public func attributes(at path: String) throws -> FileAttributes {
        if let data = files[path] {
            return FileAttributes(
                size: Int64(data.count),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isDirectory: false,
                isSymbolicLink: false
            )
        }
        guard directories.contains(path) else {
            throw CollectorError.unavailable("No such path: \(path)")
        }
        return FileAttributes(
            size: 0,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isDirectory: true,
            isSymbolicLink: false
        )
    }
}
