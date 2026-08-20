import DiffuseCapabilities
import DiffuseModels
import Foundation

/// Describes how to detect one command line developer tool.
///
/// This is the whole extension point for developer environment support.
/// Supporting a new tool is a value, not a type: declare its executable, its
/// version argument, how to parse the output, and register it. No new
/// collector, no diff engine change, no UI change.
public struct ToolAdapter: Sendable, Hashable, Identifiable {
    /// Stable identifier, e.g. `node`. Becomes the entity identity.
    public let id: String
    public let displayName: String

    /// Candidate executable names, tried in order. Some tools are installed
    /// under more than one name (`python3` before `python`).
    public let executables: [String]

    /// Arguments that make the tool print its version.
    public let versionArguments: [String]

    /// Extracts a version string from the command output.
    public let parse: @Sendable (ProcessResult) -> String?

    /// Additional metadata probes, run only when the tool is present.
    public let details: [DetailProbe]

    public let symbol: String

    /// Tools that can be slow enough to need their own guard.
    public let timeout: Duration

    public struct DetailProbe: Sendable, Hashable {
        public let key: PropertyKey
        public let arguments: [String]
        public let parse: @Sendable (ProcessResult) -> PropertyValue?

        public init(
            key: PropertyKey,
            arguments: [String],
            parse: @escaping @Sendable (ProcessResult) -> PropertyValue?
        ) {
            self.key = key
            self.arguments = arguments
            self.parse = parse
        }

        public static func == (lhs: DetailProbe, rhs: DetailProbe) -> Bool {
            lhs.key == rhs.key && lhs.arguments == rhs.arguments
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(arguments)
        }
    }

    public init(
        id: String,
        displayName: String,
        executables: [String]? = nil,
        versionArguments: [String] = ["--version"],
        symbol: String = "terminal",
        timeout: Duration = .seconds(4),
        details: [DetailProbe] = [],
        parse: @escaping @Sendable (ProcessResult) -> String? = ToolParsers.firstVersion
    ) {
        self.id = id
        self.displayName = displayName
        self.executables = executables ?? [id]
        self.versionArguments = versionArguments
        self.symbol = symbol
        self.timeout = timeout
        self.details = details
        self.parse = parse
    }

    public static func == (lhs: ToolAdapter, rhs: ToolAdapter) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// What a tool probe found.
public struct ToolObservation: Sendable, Hashable {
    public let adapter: String
    public let displayName: String
    public let executablePath: String
    public let rawVersion: String
    public let version: SemanticVersion?
    public let symbol: String
    public let details: [PropertyKey: PropertyValue]

    public init(
        adapter: String,
        displayName: String,
        executablePath: String,
        rawVersion: String,
        version: SemanticVersion?,
        symbol: String,
        details: [PropertyKey: PropertyValue]
    ) {
        self.adapter = adapter
        self.displayName = displayName
        self.executablePath = executablePath
        self.rawVersion = rawVersion
        self.version = version
        self.symbol = symbol
        self.details = details
    }
}

/// Runs tool adapters concurrently and turns the results into observations.
public struct ToolProbe: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    /// Probes every adapter concurrently. A tool that is missing, broken or
    /// hanging yields no observation and never affects the others.
    public func probe(_ adapters: [ToolAdapter]) async -> [ToolObservation] {
        await withTaskGroup(of: ToolObservation?.self) { group in
            for adapter in adapters {
                group.addTask { await probe(adapter) }
            }
            var observations: [ToolObservation] = []
            for await observation in group {
                if let observation {
                    observations.append(observation)
                }
            }
            return observations.sorted { $0.adapter < $1.adapter }
        }
    }

    public func probe(_ adapter: ToolAdapter) async -> ToolObservation? {
        var resolved: (name: String, path: String)?
        for executable in adapter.executables {
            if let path = await runner.locate(executable) {
                resolved = (executable, path)
                break
            }
        }
        guard let resolved else { return nil }

        guard
            let result = try? await runner.run(
                executable: resolved.name,
                arguments: adapter.versionArguments,
                environment: nil,
                workingDirectory: nil,
                timeout: adapter.timeout
            ),
            let rawVersion = adapter.parse(result)
        else { return nil }

        var details: [PropertyKey: PropertyValue] = [:]
        for probe in adapter.details {
            guard
                let result = try? await runner.run(
                    executable: resolved.name,
                    arguments: probe.arguments,
                    environment: nil,
                    workingDirectory: nil,
                    timeout: adapter.timeout
                ),
                let value = probe.parse(result)
            else { continue }
            details[probe.key] = value
        }

        return ToolObservation(
            adapter: adapter.id,
            displayName: adapter.displayName,
            executablePath: resolved.path,
            rawVersion: rawVersion,
            version: SemanticVersion(rawVersion),
            symbol: adapter.symbol,
            details: details
        )
    }
}
