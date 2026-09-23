import AppKit
import Foundation

/// Helpers for the extension enablement flow.
enum ExtensionStatus {

    static let extensionBundleIdentifier = "com.fosron.quicklooker.preview"

    /// Asks `pluginkit` whether the preview extension is registered and enabled.
    static var isEnabled: Bool {
        guard let output = runPluginKit(["-m", "-p", "com.apple.quicklook.preview"]) else {
            return false
        }
        for line in output.split(separator: "\n") where line.contains(extensionBundleIdentifier) {
            // Enabled entries are prefixed with "+"; disabled ones with "-".
            return line.hasPrefix("+")
        }
        return false
    }

    private static func runPluginKit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

enum SystemSettings {

    /// Opens the Extensions pane, ideally scrolled to Quick Look.
    static func openQuickLookExtensions() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
