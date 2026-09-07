import AppKit
import Foundation

/// A single block of text a user can paste into a bug report, so diagnosing a
/// problem on someone else's machine does not start with twenty questions.
enum Diagnostics {
    static func report() -> String {
        var lines: [String] = []
        func section(_ title: String) { lines.append("\n== \(title) ==") }

        let info = Bundle.main.infoDictionary
        lines.append("Ampel \(info?["CFBundleShortVersionString"] as? String ?? "?") "
            + "(\(info?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append(ProcessInfo.processInfo.isMacCatalystApp ? "catalyst" : "native")

        section("Setup")
        let hooks = HookInstaller()
        lines.append("hooks installed: \(hooks.isInstalled)")
        lines.append("statusline wrapper: \(StatuslineInstaller().isInstalled)")

        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settings) {
            let parses = (try? JSONSerialization.jsonObject(with: data)) != nil
            lines.append("settings.json: \(data.count) bytes, valid JSON: \(parses)")
        } else {
            lines.append("settings.json: not readable")
        }

        section("~/.ampel")
        let ampel = home.appendingPathComponent(".ampel")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: ampel.path) {
            for entry in entries.sorted() {
                let path = ampel.appendingPathComponent(entry).path
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
                lines.append("  \(entry)\(size.map { " (\($0) bytes)" } ?? "")")
            }
            let spool = ampel.appendingPathComponent("events")
            let pending = (try? FileManager.default.contentsOfDirectory(atPath: spool.path))?.count ?? 0
            lines.append("  events pending: \(pending)")
        } else {
            lines.append("  missing")
        }

        section("Preferences")
        for key in ["iconStyle", "usageStyle", "pulseOnAttention", "notifyOnAttention", "hasOnboarded"] {
            lines.append("  \(key): \(UserDefaults.standard.object(forKey: key) ?? "unset")")
        }

        section("Recent log")
        lines.append(tail(of: Log.fileURL, lines: 120))

        section("Crash reports")
        lines.append(contentsOf: crashReports())

        if let crash = latestCrash() {
            section("Most recent crash: \(crash.name)")
            lines.append(crash.contents)
        }

        return lines.joined(separator: "\n")
    }

    static var crashDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    private static func crashFiles() -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: crashDirectory.path)
            .filter { $0.hasPrefix("Ampel") && ($0.hasSuffix(".ips") || $0.hasSuffix(".crash")) }
            .sorted()
    }

    /// The report itself, not just its path. A person asked to "send the crash
    /// log" has to find it, and mostly does not.
    static func latestCrash() -> (name: String, contents: String)? {
        guard let name = crashFiles()?.last else { return nil }
        let url = crashDirectory.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return (name, "  (present but not readable; grant Full Disk Access or attach \(url.path))")
        }
        // The header and the faulting thread are what matter; the rest is
        // hundreds of lines of loaded binaries.
        let trimmed = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400)
        return (name, trimmed.joined(separator: "\n"))
    }

    /// A crash file newer than the one we last saw, so the app can offer the
    /// report itself instead of waiting to be asked.
    static func unreportedCrash() -> String? {
        guard let latest = crashFiles()?.last else { return nil }
        let key = "lastSeenCrashReport"
        defer { UserDefaults.standard.set(latest, forKey: key) }
        guard UserDefaults.standard.string(forKey: key) != latest else { return nil }
        return latest
    }

    /// Every report we know about, newest last.
    private static func crashReports() -> [String] {
        guard let found = crashFiles() else {
            return ["  cannot read \(crashDirectory.path)"]
        }
        guard !found.isEmpty else { return ["  none in \(crashDirectory.path)"] }
        return found.suffix(5).map { "  \(crashDirectory.path)/\($0)" }
    }

    private static func tail(of url: URL, lines count: Int) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "  (no log file yet)"
        }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }

    static func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
    }

    static func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
    }
}
