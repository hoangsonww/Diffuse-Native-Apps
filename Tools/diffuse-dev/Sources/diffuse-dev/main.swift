import DiffuseCapabilities
import DiffuseCollectors
import DiffuseCore
import DiffuseDeveloperTools
import DiffuseDiff
import DiffuseModels
import DiffuseStorage
import Foundation

// `diffuse-dev` exists for two reasons. It is a genuinely useful debugging tool
// while building collectors, and it is proof that the domain layer has no
// dependency on SwiftUI: everything the apps do — discover capabilities, take a
// snapshot, diff, validate, export — is reachable from a command line binary
// that imports no UI framework at all.

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

do {
    switch arguments.command {
    case "capabilities": try await CapabilitiesCommand.run(arguments)
    case "snapshot": try await SnapshotCommand.run(arguments)
    case "inspect": try await InspectCommand.run(arguments)
    case "diff": try await DiffCommand.run(arguments)
    case "validate": try await ValidateCommand.run(arguments)
    case "generate-fixture": try await GenerateFixtureCommand.run(arguments)
    case "privacy": try await PrivacyCommand.run(arguments)
    case "help", "--help", "-h": HelpCommand.run()
    case "version", "--version": Terminal.print("diffuse-dev \(diffuseDevVersion)")
    default:
        Terminal.error("Unknown command '\(arguments.command)'")
        HelpCommand.run()
        exit(64)
    }
} catch let error as CLIError {
    Terminal.error(error.description)
    if case .usage = error {
        exit(64)
    }
    exit(1)
} catch {
    Terminal.error(String(describing: error))
    exit(1)
}

let diffuseDevVersion: SemanticVersion = "1.0.0"

enum HelpCommand {
    static func run() {
        Terminal.print(Terminal.styled("diffuse-dev", .bold) + " — Diffuse developer tool")
        Terminal.print()
        Terminal.print(Terminal.styled("USAGE", .dim))
        Terminal.print("  diffuse-dev <command> [options]")
        Terminal.print()
        Terminal.print(Terminal.styled("COMMANDS", .dim))
        let commands: [(String, String)] = [
            ("capabilities", "List capabilities on this machine and whether each is available"),
            ("snapshot [out.json]", "Take a snapshot and print or write it"),
            ("inspect <snapshot.json>", "Summarise a snapshot file"),
            ("diff <before.json> <after.json>", "Compare two snapshot files"),
            ("validate <snapshot.json>", "Check a snapshot against the current schema"),
            ("generate-fixture <name>", "Write deterministic fixtures for the test suite"),
            ("privacy", "Print the generated privacy ledger"),
            ("version", "Print the tool version"),
        ]
        for (name, description) in commands {
            Terminal.print("  " + name.padding(toLength: 34, withPad: " ", startingAt: 0) + Terminal.styled(
                description,
                .dim
            ))
        }
        Terminal.print()
        Terminal.print(Terminal.styled("OPTIONS", .dim))
        let options: [(String, String)] = [
            ("--json", "Emit machine-readable JSON instead of formatted text"),
            ("--markdown", "Emit a Markdown report (diff only)"),
            ("--severity <level>", "informational | notable | significant | critical"),
            ("--verbose", "Include unchanged entities and full diagnostics"),
            ("--repos <a,b,c>", "Git repositories to watch when snapshotting"),
            ("--label <text>", "Label the snapshot being taken"),
            ("--pretty / --compact", "Control JSON formatting"),
        ]
        for (name, description) in options {
            Terminal.print("  " + name.padding(toLength: 34, withPad: " ", startingAt: 0) + Terminal.styled(
                description,
                .dim
            ))
        }
    }
}
