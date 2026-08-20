import DiffuseCapabilities
import DiffuseModels
import Foundation

/// The result of running a command line tool.
public struct ProcessResult: Sendable, Hashable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        exitCode == 0
    }

    /// Trimmed stdout, falling back to stderr because a surprising number of
    /// tools print their version banner there.
    public var output: String {
        let out = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? standardError.trimmingCharacters(in: .whitespacesAndNewlines) : out
    }

    public var lines: [String] {
        output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

/// Runs external commands.
///
/// Every collector that shells out goes through this protocol. Production uses
/// a real subprocess; tests use canned output. Without this seam, developer
/// tool collectors would only be testable on a machine that happens to have
/// the right tools installed at the right versions — which is to say, not
/// testable at all.
public protocol ProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: String?,
        timeout: Duration
    ) async throws -> ProcessResult

    /// Resolves an executable name to an absolute path, or `nil` if not found.
    func locate(_ executable: String) async -> String?
}

public extension ProcessRunning {
    func run(
        _ executable: String,
        _ arguments: [String] = [],
        workingDirectory: String? = nil,
        timeout: Duration = .seconds(5)
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: nil,
            workingDirectory: workingDirectory,
            timeout: timeout
        )
    }
}

#if os(macOS)

/// Runs commands as real subprocesses.
///
/// Only compiled on macOS: no other Apple platform permits spawning
/// processes, which is precisely why developer-tool capabilities are
/// macOS-only rather than being stubbed out everywhere else.
public struct SystemProcessRunner: ProcessRunning {
    /// Directories searched when `PATH` does not already contain a tool.
    /// A GUI app launched from Finder inherits a minimal `PATH` that is
    /// missing Homebrew, so relying on `PATH` alone would make Diffuse
    /// report every Homebrew-installed tool as absent.
    public static let additionalSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "/opt/homebrew/sbin",
    ]

    private let searchPaths: [String]

    public init(additionalSearchPaths: [String] = SystemProcessRunner.additionalSearchPaths) {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fromEnvironment = path.split(separator: ":").map(String.init)
        var seen = Set<String>()
        searchPaths = (fromEnvironment + additionalSearchPaths).filter { seen.insert($0).inserted }
    }

    public func locate(_ executable: String) async -> String? {
        if executable.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }
        for directory in searchPaths {
            let candidate = (directory as NSString).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: String?,
        timeout: Duration
    ) async throws -> ProcessResult {
        guard let path = await locate(executable) else {
            throw CollectorError.unavailable("\(executable) is not installed")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        var resolvedEnvironment = environment ?? ProcessInfo.processInfo.environment
        // Tools behave differently under a TTY; forcing a plain,
        // non-interactive environment keeps output parseable.
        resolvedEnvironment["PATH"] = searchPaths.joined(separator: ":")
        resolvedEnvironment["TERM"] = "dumb"
        resolvedEnvironment["NO_COLOR"] = "1"
        resolvedEnvironment["GIT_TERMINAL_PROMPT"] = "0"
        resolvedEnvironment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = resolvedEnvironment

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CollectorError.unavailable("Could not launch \(executable): \(error.localizedDescription)")
        }

        // Reading happens on detached tasks because a tool that writes more
        // than a pipe buffer will block forever if nobody drains it.
        async let outputData = Self.read(outputPipe)
        async let errorData = Self.read(errorPipe)

        let finished = await Self.wait(for: process, timeout: timeout)
        if !finished {
            process.terminate()
            // Give it a moment to die politely before reporting a timeout.
            try? await Task.sleep(for: .milliseconds(200))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            _ = await outputData
            _ = await errorData
            throw CollectorError.timedOut
        }

        return await ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    private static func read(_ pipe: Pipe) async -> Data {
        await Task.detached(priority: .utility) {
            (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        }.value
    }

    private static func wait(for process: Process, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    // Both the termination handler and the already-exited
                    // check below can fire, so the continuation is guarded
                    // against a double resume.
                    let gate = ResumeOnce(continuation)
                    process.terminationHandler = { _ in gate.resume() }
                    if !process.isRunning {
                        gate.resume()
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

/// Makes a `CheckedContinuation` safe to signal from two racing callbacks.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}

#endif

/// A process runner with canned responses, for deterministic collector tests.
public struct FakeProcessRunner: ProcessRunning {
    public struct Key: Hashable, Sendable {
        public let executable: String
        public let arguments: [String]

        public init(_ executable: String, _ arguments: [String] = []) {
            self.executable = executable
            self.arguments = arguments
        }
    }

    public var responses: [Key: ProcessResult]
    public var installed: Set<String>

    /// Executables that hang forever, for exercising timeout handling.
    public var hanging: Set<String>

    public init(
        responses: [Key: ProcessResult] = [:],
        installed: Set<String>? = nil,
        hanging: Set<String> = []
    ) {
        self.responses = responses
        self.installed = installed ?? Set(responses.keys.map(\.executable))
        self.hanging = hanging
    }

    public func locate(_ executable: String) async -> String? {
        installed.contains(executable) ? "/usr/local/bin/\(executable)" : nil
    }

    public func run(
        executable: String,
        arguments: [String],
        environment _: [String: String]?,
        workingDirectory _: String?,
        timeout: Duration
    ) async throws -> ProcessResult {
        let name = (executable as NSString).lastPathComponent

        if hanging.contains(name) {
            try? await Task.sleep(for: timeout)
            throw CollectorError.timedOut
        }
        guard installed.contains(name) else {
            throw CollectorError.unavailable("\(name) is not installed")
        }
        if let response = responses[Key(name, arguments)] {
            return response
        }
        if let response = responses[Key(name)] {
            return response
        }
        return ProcessResult(
            exitCode: 127,
            standardOutput: "",
            standardError: "no canned response for \(name) \(arguments.joined(separator: " "))"
        )
    }

    /// Builds a runner where each tool answers its version probe.
    public static func withVersions(_ versions: [String: String]) -> FakeProcessRunner {
        var responses: [Key: ProcessResult] = [:]
        for (tool, version) in versions {
            responses[Key(tool)] = ProcessResult(exitCode: 0, standardOutput: version, standardError: "")
        }
        return FakeProcessRunner(responses: responses, installed: Set(versions.keys))
    }
}
