import DiffuseModels
import Foundation

/// The developer tools Diffuse ships with support for.
///
/// This list is data. Adding Bun, Zig or Elixir support is one entry here plus
/// a parser test — no changes to the collector, the diff engine, storage,
/// search, export or any of the four apps.
public enum BuiltInToolAdapters {
    public static let languageRuntimes: [ToolAdapter] = [
        ToolAdapter(
            id: "node",
            displayName: "Node.js",
            symbol: "hexagon",
            details: [
                ToolAdapter.DetailProbe(
                    key: "execPath",
                    arguments: ["-e", "console.log(process.execPath)"],
                    parse: ToolParsers.path
                ),
            ]
        ),
        ToolAdapter(id: "deno", displayName: "Deno", symbol: "hexagon"),
        ToolAdapter(id: "bun", displayName: "Bun", symbol: "hexagon"),
        ToolAdapter(
            id: "python",
            displayName: "Python",
            executables: ["python3", "python"],
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        ToolAdapter(id: "ruby", displayName: "Ruby", symbol: "diamond"),
        ToolAdapter(
            id: "swift",
            displayName: "Swift",
            versionArguments: ["--version"],
            symbol: "swift",
            parse: ToolParsers.swiftVersion
        ),
        ToolAdapter(id: "rustc", displayName: "Rust", symbol: "gearshape.2"),
        ToolAdapter(
            id: "go",
            displayName: "Go",
            versionArguments: ["version"],
            symbol: "arrow.triangle.turn.up.right.circle",
            parse: ToolParsers.goVersion
        ),
        ToolAdapter(
            id: "java",
            displayName: "Java",
            versionArguments: ["-version"],
            symbol: "cup.and.saucer"
        ),
    ]

    public static let packageManagers: [ToolAdapter] = [
        ToolAdapter(id: "npm", displayName: "npm", symbol: "shippingbox"),
        ToolAdapter(id: "pnpm", displayName: "pnpm", symbol: "shippingbox"),
        ToolAdapter(id: "yarn", displayName: "Yarn", symbol: "shippingbox"),
        ToolAdapter(id: "uv", displayName: "uv", symbol: "shippingbox"),
        ToolAdapter(id: "pip", displayName: "pip", executables: ["pip3", "pip"], symbol: "shippingbox"),
        ToolAdapter(id: "cargo", displayName: "Cargo", symbol: "shippingbox"),
        ToolAdapter(
            id: "brew",
            displayName: "Homebrew",
            symbol: "mug",
            timeout: .seconds(6),
            details: [
                ToolAdapter.DetailProbe(key: "prefix", arguments: ["--prefix"], parse: ToolParsers.path),
            ]
        ),
    ]

    public static let infrastructure: [ToolAdapter] = [
        ToolAdapter(
            id: "docker",
            displayName: "Docker",
            versionArguments: ["--version"],
            symbol: "shippingbox.fill",
            // The Docker CLI answers instantly, but anything that talks to the
            // daemon can hang for a long time when it is not running.
            timeout: .seconds(8)
        ),
        ToolAdapter(
            id: "kubectl",
            displayName: "kubectl",
            versionArguments: ["version", "--client"],
            symbol: "helm",
            timeout: .seconds(8),
            parse: ToolParsers.kubectlVersion
        ),
        ToolAdapter(
            id: "terraform",
            displayName: "Terraform",
            versionArguments: ["version"],
            symbol: "cube.transparent",
            timeout: .seconds(8),
            parse: ToolParsers.terraformVersion
        ),
    ]

    public static let appleTooling: [ToolAdapter] = [
        ToolAdapter(
            id: "xcodebuild",
            displayName: "Xcode",
            versionArguments: ["-version"],
            symbol: "hammer.fill",
            timeout: .seconds(10),
            parse: ToolParsers.xcodeVersion
        ),
        ToolAdapter(
            id: "git",
            displayName: "Git",
            symbol: "arrow.triangle.branch"
        ),
    ]

    /// Everything, in a stable order.
    public static let all: [ToolAdapter] =
        (languageRuntimes + packageManagers + infrastructure + appleTooling)
            .sorted { $0.id < $1.id }

    public static func adapter(id: String) -> ToolAdapter? {
        all.first { $0.id == id }
    }
}
