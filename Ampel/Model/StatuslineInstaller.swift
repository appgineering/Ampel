import Foundation
import os

/// Installs a statusLine wrapper so Claude Code hands Ampel the real plan
/// limits. `statusLine` holds a single command, so the existing one is saved
/// and delegated to, the same chaining other tools already use.
final class StatuslineInstaller {
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "installer")

    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    private var wrapperURL: URL { home.appendingPathComponent(".ampel/bin/ampel-statusline") }
    private var innerURL: URL { home.appendingPathComponent(".ampel/statusline-inner") }
    private var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }

    var isInstalled: Bool {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String else { return false }
        return command == wrapperURL.path
    }

    func install() throws {
        try writeWrapper()
        var settings = readSettings() ?? [:]
        let existing = (settings["statusLine"] as? [String: Any])?["command"] as? String

        // Save whatever was there so it keeps running and can be restored.
        if let existing, existing != wrapperURL.path {
            try existing.write(to: innerURL, atomically: true, encoding: .utf8)
        } else if existing == nil {
            try? FileManager.default.removeItem(at: innerURL)
        }

        settings["statusLine"] = ["type": "command", "command": wrapperURL.path]
        try write(settings)
        log.info("statusline wrapper installed")
    }

    func uninstall() throws {
        var settings = readSettings() ?? [:]
        let inner = try? String(contentsOf: innerURL, encoding: .utf8)
        if let inner, !inner.isEmpty {
            settings["statusLine"] = ["type": "command", "command": inner]
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try write(settings)
        try? FileManager.default.removeItem(at: PlanUsage.fileURL)
        log.info("statusline wrapper removed")
    }

    // MARK: - Files

    private func writeWrapper() throws {
        try FileManager.default.createDirectory(
            at: wrapperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.wrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
    }

    /// Stores the payload, then runs the previous statusline unchanged and
    /// passes its output straight through. Must never fail loudly: a broken
    /// statusline is far more annoying than a missing usage bar.
    static let wrapper = """
    #!/bin/bash
    # ampel-statusline: captures Claude Code's statusLine payload, which is the
    # only local source of real plan limits, then runs whatever statusline was
    # configured before so nothing is lost.
    set -u
    dir="$HOME/.ampel"
    mkdir -p "$dir"
    input="$(cat)"
    tmp="$dir/.usage-$$"
    printf '%s' "$input" > "$tmp" && mv "$tmp" "$dir/usage.json"

    inner="$dir/statusline-inner"
    if [ -s "$inner" ]; then
      printf '%s' "$input" | bash -c "$(cat "$inner")"
      exit 0
    fi

    # No statusline was configured before, so print a useful one rather than
    # leaving an empty row. Quotes are stripped first so the patterns need none,
    # which keeps this readable and free of jq.
    flat="$(printf '%s' "$input" | tr -d ' \\n\\"')"
    pct() {
      printf '%s' "$flat" | grep -oE "$1:\\{[^}]*used_percentage:[0-9.]+" | grep -oE '[0-9.]+$'
    }
    five="$(pct five_hour)"
    seven="$(pct seven_day)"
    out=""
    [ -n "$five" ] && out="session ${five%.*}%"
    [ -n "$seven" ] && out="${out:+$out · }week ${seven%.*}%"
    [ -n "$out" ] && printf 'Claude: %s\\n' "$out"
    exit 0

    """

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func write(_ settings: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.bak-\(Int(Date().timeIntervalSince1970))")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.copyItem(at: settingsURL, to: backup)
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
