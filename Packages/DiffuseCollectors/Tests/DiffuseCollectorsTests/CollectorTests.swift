import DiffuseCapabilities
import DiffuseCollectors
import DiffuseDeveloperTools
import DiffuseModels
import DiffuseTestSupport
import Foundation
import Testing

private let context = CollectionContext(
    startedAt: SnapshotBuilder.referenceDate,
    platform: Platform.current
)

@Suite("Shared collectors")
struct SharedCollectorTests {
    @Test("The system collector reads real state and fills every declared property")
    func systemInfo() async throws {
        let snapshot = try await SystemInfoCollector().collect(context: context)
        let entity = try #require(snapshot.entities.first)

        #expect(snapshot.entities.count == 1)
        #expect(!entity[.osVersion].isAbsent)
        #expect(entity[.coreCount].numericValue ?? 0 > 0)
        #expect(entity[.physicalMemory].numericValue ?? 0 > 0)

        // Anything the collector emits must be described by its own schema,
        // or the UI and diff engine would have to guess.
        let descriptor = try #require(SystemInfoSnapshot.schema.descriptor(for: entity.kind))
        let declared = Set(descriptor.properties.map(\.key))
        for key in entity.sortedPropertyKeys {
            #expect(declared.contains(key), "\(key) is emitted but not declared")
        }
    }

    @Test("Boot time is rounded so clock jitter does not read as a reboot")
    func bootTimeStability() async throws {
        let first = try await SystemInfoCollector().collect(context: context)
        let second = try await SystemInfoCollector().collect(
            context: CollectionContext(
                startedAt: SnapshotBuilder.referenceDate.addingTimeInterval(5),
                platform: Platform.current
            )
        )

        let firstBoot = try #require(first.entities.first?[.bootedAt].numericValue)
        let secondBoot = try #require(second.entities.first?[.bootedAt].numericValue)
        #expect(abs(firstBoot - secondBoot) <= 60)
    }

    @Test("The storage collector reports a usable volume")
    func storage() async throws {
        let snapshot = try await StorageCollector().collect(context: context)
        let volume = try #require(snapshot.entities.first)

        #expect(snapshot.status == .collected)
        #expect(volume[.totalCapacity].numericValue ?? 0 > 0)
        #expect(volume[.availableCapacity].numericValue ?? 0 >= 0)
    }

    @Test("Every storage property is declared by the schema")
    func storageSchemaCompleteness() async throws {
        let snapshot = try await StorageCollector().collect(context: context)
        let volume = try #require(snapshot.entities.first)
        let descriptor = try #require(StorageSnapshot.schema.descriptor(for: volume.kind))
        let declared = Set(descriptor.properties.map(\.key))

        for key in volume.sortedPropertyKeys {
            #expect(declared.contains(key), "\(key) is emitted but not declared")
        }

        let declaredAttributes = Set(StorageSnapshot.schema.attributes.map(\.key))
        for key in snapshot.attributes.keys {
            #expect(declaredAttributes.contains(key), "attribute \(key) is emitted but not declared")
        }
    }

    @Test("Network interfaces are enumerated with stable identities")
    func networkInterfaces() async throws {
        let snapshot = try await NetworkInterfaceCollector().collect(context: context)
        #expect(!snapshot.entities.isEmpty)

        let identities = snapshot.entities.map(\.identity)
        #expect(Set(identities).count == identities.count, "Interface identities must be unique")
    }

    @Test("Loopback is excluded by default because it is never interesting")
    func loopbackExcluded() async throws {
        let snapshot = try await NetworkInterfaceCollector().collect(context: context)
        #expect(!snapshot.entities.contains { $0.identity.value == "lo0" })

        let withLoopback = try await NetworkInterfaceCollector(includesLoopback: true).collect(context: context)
        #expect(withLoopback.entities.contains { $0.identity.value == "lo0" })
    }

    @Test("Interface type names are derived from the BSD prefix")
    func interfaceTypes() {
        #expect(NetworkInterfaceSnapshot.describeType("en0") == "Ethernet or Wi-Fi")
        #expect(NetworkInterfaceSnapshot.describeType("utun3") == "Tunnel or VPN")
        #expect(NetworkInterfaceSnapshot.describeType("pdp_ip0") == "Cellular")
        #expect(NetworkInterfaceSnapshot.describeType("lo0") == "Loopback")
    }

    @Test("The network path collector returns within its deadline", .timeLimit(.minutes(1)))
    func networkPath() async throws {
        let snapshot = try await NetworkPathCollector().collect(context: context)
        let path = try #require(snapshot.entities.first)
        #expect(!path[.pathStatus].isAbsent)
        #expect(!path[.interfaceType].isAbsent)
    }
}

#if os(macOS)

@Suite("macOS collectors")
struct MacCollectorTests {
    @Test("Hardware reads the machine's real chip and memory")
    func hardware() async throws {
        let snapshot = try await MacHardwareCollector().collect(context: context)
        let machine = try #require(snapshot.entities.first)

        #expect(!machine[.modelIdentifier].isAbsent)
        #expect(machine[.coreCount].numericValue ?? 0 > 0)
        #expect(machine[.physicalMemory].numericValue ?? 0 > 0)
    }

    @Test("Displays are identified by hardware ID rather than a transient handle")
    func displays() async throws {
        let snapshot = try await MacDisplayCollector().collect(context: context)

        for display in snapshot.entities {
            #expect(!display.identity.value.isEmpty)
            #expect(!display[.resolution].isAbsent)
        }
        #expect(snapshot.attributes["displayCount"] == .integer(Int64(snapshot.entities.count)))
    }

    @Test("A Mac with no battery is unavailable, not failed")
    func power() async throws {
        let snapshot = try await MacPowerCollector().collect(context: context)
        #expect(snapshot.status == .collected || snapshot.status == .unavailable)
        if snapshot.status == .unavailable {
            #expect(snapshot.entities.isEmpty)
        }
    }

    @Test("Applications are read from Info.plist without touching app data")
    func applications() async throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleIdentifier</key><string>com.example.thing</string>
          <key>CFBundleName</key><string>Thing</string>
          <key>CFBundleShortVersionString</key><string>2.1.0</string>
          <key>CFBundleVersion</key><string>2100</string>
        </dict></plist>
        """

        let fileSystem = FakeFileSystem(
            textFiles: ["/Apps/Thing.app/Contents/Info.plist": plist],
            directories: ["/Apps"]
        )

        let snapshot = try await MacApplicationsCollector(searchPaths: ["/Apps"], fileSystem: fileSystem)
            .collect(context: context)
        let app = try #require(snapshot.entities.first)

        #expect(app.identity.value == "com.example.thing")
        #expect(app.displayName == "Thing")
        #expect(app[.version] == .version(SemanticVersion(2, 1, 0)))
        #expect(app[.buildNumber] == .string("2100"))
    }

    @Test("A bundle without an identifier is skipped rather than guessed at")
    func malformedBundle() async throws {
        let fileSystem = FakeFileSystem(
            textFiles: ["/Apps/Broken.app/Contents/Info.plist": "not a plist"],
            directories: ["/Apps"]
        )
        let snapshot = try await MacApplicationsCollector(searchPaths: ["/Apps"], fileSystem: fileSystem)
            .collect(context: context)
        #expect(snapshot.entities.isEmpty)
    }

    @Test("Earlier search paths win when an app is installed twice")
    func duplicateApplications() async throws {
        func plist(_ version: String) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
              <key>CFBundleIdentifier</key><string>com.example.thing</string>
              <key>CFBundleName</key><string>Thing</string>
              <key>CFBundleShortVersionString</key><string>\(version)</string>
            </dict></plist>
            """
        }

        let fileSystem = FakeFileSystem(
            textFiles: [
                "/First/Thing.app/Contents/Info.plist": plist("1.0.0"),
                "/Second/Thing.app/Contents/Info.plist": plist("2.0.0"),
            ],
            directories: ["/First", "/Second"]
        )

        let snapshot = try await MacApplicationsCollector(
            searchPaths: ["/First", "/Second"],
            fileSystem: fileSystem
        ).collect(context: context)

        #expect(snapshot.entities.count == 1)
        #expect(snapshot.entities.first?[.version] == .version(SemanticVersion(1, 0, 0)))
    }

    @Test("Developer tools are discovered from adapters, with no per-tool code")
    func developerTools() async throws {
        let runner = FakeProcessRunner.withVersions([
            "node": "v24.6.0",
            "git": "git version 2.46.0",
        ])

        let snapshot = try await MacDeveloperToolsCollector(runner: runner).collect(context: context)

        #expect(snapshot.entities.count == 2)
        #expect(snapshot.attributes["toolCount"] == .integer(2))
        let node = try #require(snapshot.entities.first { $0.identity.value == "node" })
        #expect(node[.version] == .version(SemanticVersion(24, 6, 0)))
    }

    @Test("With no tools installed the section is unavailable, not empty-but-fine")
    func noDeveloperTools() async throws {
        let snapshot = try await MacDeveloperToolsCollector(runner: FakeProcessRunner(installed: []))
            .collect(context: context)
        #expect(snapshot.status == .unavailable)
        #expect(!snapshot.diagnostics.isEmpty)
    }

    @Test("Developer tool probing is skipped during a background capture")
    func backgroundSkipsToolProbing() async throws {
        let runner = FakeProcessRunner.withVersions(["node": "v24.6.0"])
        let backgroundContext = CollectionContext(
            startedAt: SnapshotBuilder.referenceDate,
            platform: .macOS,
            isBackground: true
        )

        let snapshot = try await MacDeveloperToolsCollector(runner: runner).collect(context: backgroundContext)
        #expect(snapshot.entities.isEmpty)
    }

    @Test("Git metadata is read without ever touching file contents")
    func git() async throws {
        let runner = FakeProcessRunner(
            responses: [
                FakeProcessRunner.Key("git", ["-C", "/repo", "rev-parse", "--show-toplevel"]):
                    ProcessResult(exitCode: 0, standardOutput: "/repo", standardError: ""),
                FakeProcessRunner.Key("git", ["-C", "/repo", "rev-parse", "--abbrev-ref", "HEAD"]):
                    ProcessResult(exitCode: 0, standardOutput: "feature/webrtc", standardError: ""),
                FakeProcessRunner.Key("git", ["-C", "/repo", "rev-parse", "--short=8", "HEAD"]):
                    ProcessResult(exitCode: 0, standardOutput: "c31a8207", standardError: ""),
                FakeProcessRunner.Key("git", ["-C", "/repo", "status", "--porcelain=v1", "--untracked-files=normal"]):
                    ProcessResult(
                        exitCode: 0,
                        standardOutput: " M Sources/App.swift\n M Sources/Other.swift\n?? Notes.md",
                        standardError: ""
                    ),
                FakeProcessRunner.Key(
                    "git",
                    ["-C", "/repo", "rev-list", "--left-right", "--count", "@{upstream}...HEAD"]
                ):
                    ProcessResult(exitCode: 0, standardOutput: "1\t3", standardError: ""),
                FakeProcessRunner.Key("git", ["-C", "/repo", "config", "--get", "remote.origin.url"]):
                    ProcessResult(exitCode: 0, standardOutput: "git@github.com:owner/repo.git", standardError: ""),
            ],
            installed: ["git"]
        )

        let snapshot = try await MacGitCollector(repositoryPaths: ["/repo"], runner: runner)
            .collect(context: context)
        let repository = try #require(snapshot.entities.first)

        #expect(repository[.branch] == .string("feature/webrtc"))
        #expect(repository[.commit] == .identifier("c31a8207"))
        #expect(repository[.modifiedFileCount] == .integer(2))
        #expect(repository[.untrackedFileCount] == .integer(1))
        #expect(repository[.aheadCount] == .integer(3))
        #expect(repository[.behindCount] == .integer(1))
        #expect(repository["remoteHost"] == .string("github.com"))

        let rendered = repository.searchText
        #expect(!rendered.contains("app.swift"), "File names must never reach a snapshot")
        #expect(!rendered.contains("owner/repo"), "The remote path must be reduced to its host")
    }

    @Test(
        "Remote URLs reduce to a host in every common form",
        arguments: [
            ("git@github.com:owner/repo.git", "github.com"),
            ("https://github.com/owner/repo", "github.com"),
            ("ssh://git@git.internal.example:2222/team/repo.git", "git.internal.example"),
        ]
    )
    func remoteHostExtraction(url: String, expected: String) {
        #expect(MacGitCollector.host(of: url) == expected)
    }

    @Test("Porcelain status counts modified and untracked separately")
    func statusCounting() {
        let counts = MacGitCollector.countStatus(" M a.swift\nA  b.swift\n?? c.swift\n?? d.swift")
        #expect(counts.modified == 2)
        #expect(counts.untracked == 2)
    }

    @Test("A path that is not a repository is reported, not silently dropped")
    func nonRepositoryPath() async throws {
        let runner = FakeProcessRunner(
            responses: [
                FakeProcessRunner.Key("git", ["-C", "/not-a-repo", "rev-parse", "--show-toplevel"]):
                    ProcessResult(exitCode: 128, standardOutput: "", standardError: "not a git repository"),
            ],
            installed: ["git"]
        )

        let snapshot = try await MacGitCollector(repositoryPaths: ["/not-a-repo"], runner: runner)
            .collect(context: context)

        #expect(snapshot.entities.isEmpty)
        #expect(snapshot.diagnostics.contains { $0.level == .warning })
    }

    @Test("Process listing aggregates by name and discards arguments")
    func processes() async throws {
        let runner = FakeProcessRunner(
            responses: [
                FakeProcessRunner.Key("ps", ["-axco", "rss=,pcpu=,comm="]):
                    ProcessResult(
                        exitCode: 0,
                        standardOutput: """
                        102400  1.5 Safari
                         51200  0.5 Safari
                        204800 12.0 Xcode
                          1024  0.0 launchd
                        """,
                        standardError: ""
                    ),
            ],
            installed: ["ps"]
        )

        let snapshot = try await MacProcessCollector(runner: runner, limit: 10).collect(context: context)
        let safari = try #require(snapshot.entities.first { $0.identity.value == "safari" })

        #expect(snapshot.attributes[.processCount] == .integer(4))
        #expect(safari[.memoryFootprint] == .bytes(Int64(102_400 + 51200) * 1024))
        #expect(snapshot.entities.count == 3)
    }

    @Test("The registry lists every macOS capability exactly once")
    func registry() {
        let registry = MacCapabilityRegistry()
        let ids = registry.capabilityIDs

        #expect(Set(ids).count == ids.count)
        #expect(ids == ids.sorted())
        for expected: CapabilityID in [
            "system.info", "hardware.machine", "display.configuration", "power.battery",
            "network.interfaces", "network.path", "network.wifi", "storage.volumes",
            "software.applications", "system.processes", "development.tools", "development.git",
        ] {
            #expect(ids.contains(expected), "Missing \(expected)")
        }
    }

    @Test("Sensitive capabilities are classified as such")
    func privacyClassification() throws {
        let registry = MacCapabilityRegistry()

        let wifi = try #require(registry.capability(with: "network.wifi"))
        #expect(wifi.metadata.privacy == .sensitive)
        #expect(!wifi.metadata.permissions.isEmpty)

        let git = try #require(registry.capability(with: "development.git"))
        #expect(git.metadata.privacy == .sensitive)

        let processes = try #require(registry.capability(with: "system.processes"))
        #expect(!processes.metadata.isEnabledByDefault, "Process listing should be opt-in")
    }

    @Test("Every capability explains what it collects")
    func collectionDescriptions() {
        for capability in MacCapabilityRegistry().capabilities {
            let description = capability.metadata.collectionDescription
            #expect(description.count > 40, "\(capability.id) needs a real privacy description")
            #expect(description.hasSuffix("."), "\(capability.id) description should be a sentence")
        }
    }
}

#endif
