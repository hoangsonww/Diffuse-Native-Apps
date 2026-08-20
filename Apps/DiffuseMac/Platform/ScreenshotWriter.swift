import AppKit
import Foundation

/// Writes a PNG of the front window. Prefers Screen Recording via
/// `screencapture` when available; falls back to caching the content view.
@MainActor
enum ScreenshotWriter {
    static func writeIfRequested(after delay: TimeInterval = 2.4) {
        guard let path = ProcessInfo.processInfo.environment["DIFFUSE_WRITE_SCREENSHOT"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            write(to: URL(fileURLWithPath: path))
            if ProcessInfo.processInfo.environment["DIFFUSE_WRITE_SCREENSHOT_EXIT"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    static func write(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
           window.windowNumber > 0 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", url.path]
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
                return
            }
        }

        let windows = NSApplication.shared.windows
        let window = windows.first { $0.isVisible && $0.contentView != nil && $0.canBecomeMain } ?? windows.first
        guard let view = window?.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
