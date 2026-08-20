import DiffuseCapabilities
import DiffuseDeveloperTools
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

/// Parser tests run against output captured verbatim from the real tools.
///
/// Version banners are gratuitously inconsistent, and every one of these
/// strings is a shape that broke a naive regex at some point.
@Suite("Version parsers")
struct ToolParserTests {
    @Test(
        "The generic parser handles the common shapes",
        arguments: [
            ("v24.6.0", "24.6.0"),
            ("24.6.0", "24.6.0"),
            ("10.8.2", "10.8.2"),
            ("Python 3.12.4", "3.12.4"),
            ("rustc 1.81.0 (eeb90cda1 2024-09-04)", "1.81.0"),
            ("Docker version 27.2.0, build 3ab4256", "27.2.0"),
            ("git version 2.46.0", "2.46.0"),
            ("1.22", "1.22"),
        ]
    )
    func genericParsing(output: String, expected: String) {
        let result = ProcessResult(exitCode: 0, standardOutput: output, standardError: "")
        #expect(ToolParsers.firstVersion(result) == expected)
    }

    @Test("Go prints its version in the middle of a sentence")
    func goParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: "go version go1.23.1 darwin/arm64",
            standardError: ""
        )
        #expect(ToolParsers.goVersion(result) == "1.23.1")
    }

    @Test("Terraform prints a changelog URL after its version")
    func terraformParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: """
            Terraform v1.9.5
            on darwin_arm64

            Your version of Terraform is out of date! The latest version
            is 1.9.8. You can update by downloading from https://www.terraform.io/downloads.html
            """,
            standardError: ""
        )
        #expect(ToolParsers.terraformVersion(result) == "1.9.5", "The advertised newer version must not win")
    }

    @Test("kubectl labels the client version explicitly")
    func kubectlParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: "Client Version: v1.31.0\nKustomize Version: v5.4.2",
            standardError: ""
        )
        #expect(ToolParsers.kubectlVersion(result) == "1.31.0")
    }

    @Test("Xcode prints its version above its build number")
    func xcodeParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: "Xcode 26.6\nBuild version 17F113",
            standardError: ""
        )
        #expect(ToolParsers.xcodeVersion(result) == "26.6")
    }

    @Test("Swift buries its version behind the driver's own version")
    func swiftParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: """
            swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
            Target: arm64-apple-macosx26.0
            """,
            standardError: ""
        )
        #expect(ToolParsers.swiftVersion(result) == "6.3.3", "The driver version must not be mistaken for Swift's")
    }

    @Test("Java prints its version to standard error")
    func javaParsing() {
        let result = ProcessResult(
            exitCode: 0,
            standardOutput: "",
            standardError: "openjdk version \"21.0.4\" 2024-07-16"
        )
        #expect(ToolParsers.firstVersion(result) == "21.0.4")
    }

    @Test("Unparseable output yields nil rather than a wrong answer")
    func unparseable() {
        let result = ProcessResult(exitCode: 0, standardOutput: "command not found", standardError: "")
        #expect(ToolParsers.firstVersion(result) == nil)
    }

    @Test("Key/value output parses into a dictionary")
    func keyValues() {
        let parsed = ToolParsers.keyValues("""
        NAME="Ubuntu"
        VERSION_ID=24.04
        PRETTY: Ubuntu 24.04 LTS
        """)
        #expect(parsed["NAME"] == "Ubuntu")
        #expect(parsed["VERSION_ID"] == "24.04")
        #expect(parsed["PRETTY"] == "Ubuntu 24.04 LTS")
    }
}

@Suite("Tool discovery")
struct ToolProbeTests {
    @Test("An installed tool produces an observation with a parsed version")
    func detectsInstalledTool() async throws {
        let runner = FakeProcessRunner.withVersions(["node": "v24.6.0"])
        let adapter = try #require(BuiltInToolAdapters.adapter(id: "node"))
        let observation = try #require(try await ToolProbe(runner: runner).probe(adapter))

        #expect(observation.adapter == "node")
        #expect(observation.rawVersion == "24.6.0")
        #expect(observation.version == SemanticVersion(24, 6, 0))
        #expect(observation.executablePath.hasSuffix("node"))
    }

    @Test("A missing tool produces no observation, not an error entry")
    func missingToolIsSilent() async throws {
        let runner = FakeProcessRunner(installed: [])
        let adapter = try #require(BuiltInToolAdapters.adapter(id: "docker"))
        let observation = try await ToolProbe(runner: runner).probe(adapter)
        #expect(observation == nil, "Diffuse must not show 'Docker: not installed' for tools you never had")
    }

    @Test("Alternative executable names are tried in order")
    func alternativeExecutables() async throws {
        // Only `python3` exists; the adapter also knows about bare `python`.
        let runner = FakeProcessRunner.withVersions(["python3": "Python 3.12.4"])
        let adapter = try #require(BuiltInToolAdapters.adapter(id: "python"))
        let observation = try #require(try await ToolProbe(runner: runner).probe(adapter))
        #expect(observation.rawVersion == "3.12.4")
    }

    @Test("A tool that hangs is dropped without stalling the others", .timeLimit(.minutes(1)))
    func hangingToolIsDropped() async throws {
        let runner = FakeProcessRunner(
            responses: [FakeProcessRunner.Key("node"): ProcessResult(
                exitCode: 0,
                standardOutput: "v24.6.0",
                standardError: ""
            )],
            installed: ["node", "docker"],
            hanging: ["docker"]
        )

        let node = try #require(BuiltInToolAdapters.adapter(id: "node"))
        let docker = try #require(BuiltInToolAdapters.adapter(id: "docker"))
        let observations = try await ToolProbe(runner: runner).probe([node, docker])

        #expect(observations.map(\.adapter) == ["node"])
    }

    @Test("Detail probes attach extra properties when they succeed")
    func detailProbes() async throws {
        let runner = FakeProcessRunner(
            responses: [
                FakeProcessRunner.Key("brew"): ProcessResult(
                    exitCode: 0,
                    standardOutput: "Homebrew 4.3.20",
                    standardError: ""
                ),
                FakeProcessRunner.Key("brew", ["--prefix"]): ProcessResult(
                    exitCode: 0,
                    standardOutput: "/opt/homebrew",
                    standardError: ""
                ),
            ],
            installed: ["brew"]
        )

        let adapter = try #require(BuiltInToolAdapters.adapter(id: "brew"))
        let observation = try #require(try await ToolProbe(runner: runner).probe(adapter))
        #expect(observation.details["prefix"] == .path("/opt/homebrew"))
    }

    @Test("Probing many tools is concurrent and returns a stable order")
    func stableOrdering() async {
        let runner = FakeProcessRunner.withVersions([
            "node": "v24.6.0", "git": "git version 2.46.0", "go": "go version go1.23.1 darwin/arm64",
        ])
        let adapters = BuiltInToolAdapters.all

        let first = await ToolProbe(runner: runner).probe(adapters).map(\.adapter)
        let second = await ToolProbe(runner: runner).probe(adapters).map(\.adapter)

        #expect(first == second)
        #expect(first == first.sorted())
    }
}

@Suite("Adapter catalogue")
struct AdapterCatalogueTests {
    @Test("Adapter identifiers are unique")
    func uniqueIdentifiers() {
        let ids = BuiltInToolAdapters.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every adapter declares an executable and a version argument")
    func wellFormed() {
        for adapter in BuiltInToolAdapters.all {
            #expect(!adapter.executables.isEmpty, "\(adapter.id) has no executable")
            #expect(!adapter.versionArguments.isEmpty, "\(adapter.id) has no version arguments")
            #expect(!adapter.displayName.isEmpty, "\(adapter.id) has no display name")
        }
    }

    @Test("Tools that can talk to a daemon get a longer deadline")
    func daemonToolsHaveLongerTimeouts() throws {
        let docker = try #require(BuiltInToolAdapters.adapter(id: "docker"))
        let node = try #require(BuiltInToolAdapters.adapter(id: "node"))
        #expect(docker.timeout > node.timeout)
    }

    @Test("The catalogue covers the toolchains the product promises")
    func coverage() {
        let ids = Set(BuiltInToolAdapters.all.map(\.id))
        for expected in ["node", "python", "git", "docker", "brew", "rustc", "go", "terraform", "swift"] {
            #expect(ids.contains(expected), "Missing adapter for \(expected)")
        }
    }
}

@Suite("Process results")
struct ProcessResultTests {
    @Test("Output falls back to standard error when stdout is empty")
    func stderrFallback() {
        let result = ProcessResult(exitCode: 0, standardOutput: "  \n", standardError: "the real output")
        #expect(result.output == "the real output")
    }

    @Test("Success is exit code zero")
    func exitCodes() {
        #expect(ProcessResult(exitCode: 0, standardOutput: "", standardError: "").succeeded)
        #expect(!ProcessResult(exitCode: 1, standardOutput: "", standardError: "").succeeded)
    }

    @Test("A missing canned response is a clear failure, not a silent empty string")
    func fakeRunnerFallback() async throws {
        let runner = FakeProcessRunner(installed: ["thing"])
        let result = try await runner.run("thing", ["--unknown"])
        #expect(!result.succeeded)
        #expect(result.standardError.contains("no canned response"))
    }
}
