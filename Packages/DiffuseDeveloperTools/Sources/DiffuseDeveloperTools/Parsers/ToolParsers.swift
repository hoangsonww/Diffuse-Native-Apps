import DiffuseModels
import Foundation

/// Version-string extraction for tool output.
///
/// Every one of these is a pure `String -> String?` and is covered by tests
/// against real captured output, because "parse the version" is deceptively
/// varied: `v24.6.0`, `Python 3.12.4`, `go version go1.23.1 darwin/arm64`,
/// `Docker version 27.2.0, build 3ab4256`.
public enum ToolParsers {
    /// Matches the first `1.2`, `1.2.3` or `v1.2.3-beta.1` in the output.
    public static let firstVersion: @Sendable (ProcessResult) -> String? = { result in
        firstVersion(in: result.output)
    }

    public static func firstVersion(in text: String) -> String? {
        guard let regex = versionRegex else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let matchRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[matchRange])
    }

    /// Returns the whole first line, trimmed. Used for tools whose banner is
    /// more informative than the bare number.
    public static let firstLine: @Sendable (ProcessResult) -> String? = { result in
        result.lines.first.map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Extracts the version from `go version go1.23.1 darwin/arm64`.
    public static let goVersion: @Sendable (ProcessResult) -> String? = { result in
        let text = result.output
        let searchStart = text.range(of: "version")?.upperBound ?? text.startIndex
        guard let range = text.range(of: "go", range: searchStart ..< text.endIndex) else {
            return firstVersion(in: text)
        }
        return firstVersion(in: String(text[range.upperBound...]))
    }

    /// `Terraform v1.9.5` on the first line, then a changelog URL.
    public static let terraformVersion: @Sendable (ProcessResult) -> String? = { result in
        result.lines.first.flatMap { firstVersion(in: $0) }
    }

    /// `Client Version: v1.31.0` from `kubectl version --client`.
    public static let kubectlVersion: @Sendable (ProcessResult) -> String? = { result in
        result.lines
            .first { $0.localizedCaseInsensitiveContains("client version") }
            .flatMap { firstVersion(in: $0) }
            ?? firstVersion(in: result.output)
    }

    /// Handles `xcodebuild -version` output spanning two lines.
    public static let xcodeVersion: @Sendable (ProcessResult) -> String? = { result in
        result.lines
            .first { $0.hasPrefix("Xcode") }
            .flatMap { firstVersion(in: $0) }
            ?? firstVersion(in: result.output)
    }

    /// `swift-driver version: 1.x Apple Swift version 6.3.3 (...)`
    public static let swiftVersion: @Sendable (ProcessResult) -> String? = { result in
        guard let range = result.output.range(of: "Swift version ") else {
            return firstVersion(in: result.output)
        }
        return firstVersion(in: String(result.output[range.upperBound...]))
    }

    // MARK: - Value probes

    /// A probe parser that reports the trimmed output as a string.
    public static let text: @Sendable (ProcessResult) -> PropertyValue? = { result in
        let value = result.output
        return value.isEmpty ? nil : .string(value)
    }

    /// A probe parser that reports the trimmed output as a path.
    public static let path: @Sendable (ProcessResult) -> PropertyValue? = { result in
        let value = result.output
        return value.isEmpty ? nil : .path(value)
    }

    /// A probe parser that counts non-empty output lines.
    public static let lineCount: @Sendable (ProcessResult) -> PropertyValue? = { result in
        .integer(Int64(result.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count))
    }

    // MARK: - Generic helpers

    /// Parses `key=value` or `key: value` output into a dictionary.
    public static func keyValues(_ text: String, separators: [Character] = ["=", ":"]) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let index = line.firstIndex(where: { separators.contains($0) }) else { continue }
            let key = line[line.startIndex ..< index].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return result
    }

    private nonisolated(unsafe) static let versionRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"v?(\d+(?:\.\d+){0,3}(?:[-+][0-9A-Za-z.\-]+)?)"#
    )
}
