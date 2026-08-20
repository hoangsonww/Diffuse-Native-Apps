import Foundation

/// A very small argument parser.
///
/// Hand-rolled rather than pulling in swift-argument-parser: Diffuse has zero
/// third-party dependencies, which keeps CI hermetic and keeps `Package.resolved`
/// from becoming a supply-chain surface. The CLI's grammar is a verb plus a few
/// flags, which does not justify a dependency.
struct Arguments {
    let command: String
    let positionals: [String]
    private let flags: [String: String?]

    init(_ raw: [String]) {
        var rest = raw
        command = rest.first.map { $0.hasPrefix("-") ? "help" : rest.removeFirst() } ?? "help"

        var positionals: [String] = []
        var flags: [String: String?] = [:]
        var index = 0

        while index < rest.count {
            let token = rest[index]
            if token.hasPrefix("--") {
                let name = String(token.dropFirst(2))
                if let equals = name.firstIndex(of: "=") {
                    flags[String(name[name.startIndex ..< equals])] = String(name[name.index(after: equals)...])
                } else if index + 1 < rest.count, !rest[index + 1].hasPrefix("-") {
                    flags[name] = rest[index + 1]
                    index += 1
                } else {
                    flags[name] = String?.none
                }
            } else {
                positionals.append(token)
            }
            index += 1
        }

        self.positionals = positionals
        self.flags = flags
    }

    func has(_ name: String) -> Bool {
        flags.keys.contains(name)
    }

    func value(_ name: String) -> String? {
        flags[name] ?? nil
    }

    func value(_ name: String, default defaultValue: String) -> String {
        value(name) ?? defaultValue
    }

    func integer(_ name: String) -> Int? {
        value(name).flatMap(Int.init)
    }

    func positional(_ index: Int) -> String? {
        index < positionals.count ? positionals[index] : nil
    }
}

/// Terminal output helpers.
///
/// Colour is disabled when stdout is not a TTY or when `NO_COLOR` is set, so
/// piping the CLI into a file or a CI log produces clean text.
enum Terminal {
    static let supportsColor: Bool = {
        guard ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return false }
        guard ProcessInfo.processInfo.environment["TERM"] != "dumb" else { return false }
        return isatty(STDOUT_FILENO) == 1
    }()

    enum Style: String {
        case reset = "\u{1B}[0m"
        case bold = "\u{1B}[1m"
        case dim = "\u{1B}[2m"
        case red = "\u{1B}[31m"
        case green = "\u{1B}[32m"
        case yellow = "\u{1B}[33m"
        case blue = "\u{1B}[34m"
        case magenta = "\u{1B}[35m"
        case cyan = "\u{1B}[36m"
    }

    static func styled(_ text: String, _ styles: Style...) -> String {
        guard supportsColor, !styles.isEmpty else { return text }
        return styles.map(\.rawValue).joined() + text + Style.reset.rawValue
    }

    static func print(_ text: String = "") {
        Swift.print(text)
    }

    static func error(_ text: String) {
        FileHandle.standardError.write(Data((styled("error: ", .red, .bold) + text + "\n").utf8))
    }

    static func heading(_ text: String) {
        print(styled(text, .bold))
        print(styled(String(repeating: "─", count: max(text.count, 12)), .dim))
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failure(String)

    var description: String {
        switch self {
        case let .usage(message), let .failure(message): message
        }
    }
}

extension URL {
    /// Resolves a user-supplied path argument, expanding `~` and relative paths
    /// against the current working directory.
    static func resolving(path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
    }
}
