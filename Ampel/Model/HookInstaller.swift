import Foundation
import os

/// First-run setup. See SPEC §8.
/// Checks that ~/.ampel/bin/ampel-hook exists and is executable and that all
/// eight hook entries are present in ~/.claude/settings.json.
/// install(): backup settings.json as settings.json.bak-<epoch>, write the
/// script, MERGE the hooks block — preserve unrelated settings and append to
/// (never replace) existing hooks on the same events.
final class HookInstaller {
    private let log = Log("installer")

    /// Events Ampel listens to. `UserPromptSubmit` and `Stop` take no matcher.
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "Notification", "Stop", "SubagentStop", "SessionEnd"]
    private static let matcherless: Set<String> = ["UserPromptSubmit", "Stop"]

    /// Injectable so tests can run the real merge against a throwaway home.
    /// `homeDirectoryForCurrentUser` deliberately ignores $HOME, so overriding
    /// the environment is not an option.
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private var scriptURL: URL { home.appendingPathComponent(".ampel/bin/ampel-hook") }
    private var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }

    private func command(for event: String) -> String { "~/.ampel/bin/ampel-hook \(event)" }

    var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else { return false }
        guard let settings = readSettings() else { return false }
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return Self.events.allSatisfy { event in
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .contains { $0["command"] as? String == command(for: event) }
            }
        }
    }

    /// settings.json outlives ~/.ampel. If the hooks are still registered but
    /// the script they call is gone, every hook silently fails and Ampel goes
    /// blind, so put the script back rather than waiting to be asked.
    func repairIfNeeded() {
        guard !FileManager.default.isExecutableFile(atPath: scriptURL.path), hooksRegistered else { return }
        try? writeScript()
        log.info("restored a missing hook script")
    }

    private var hooksRegistered: Bool {
        guard let settings = readSettings() else { return false }
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return Self.events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .contains { $0["command"] as? String == command(for: event) }
            }
        }
    }

    /// Returns the backup that was made, or nil when there was no settings
    /// file to lose, so the menu can say what actually happened.
    @discardableResult
    func install() throws -> URL? {
        try writeScript()
        let backup = try mergeSettings()
        log.info("hooks installed")
        return backup
    }

    // MARK: - Script

    private func writeScript() throws {
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    /// Kept byte-identical to SPEC §2.1.
    static let script = """
    #!/bin/bash
    # Usage: ampel-hook <EventName>   — stdin: Claude Code hook JSON payload
    set -u
    dir="$HOME/.ampel/events"
    mkdir -p "$dir"
    payload="$(cat)"
    [ -z "$payload" ] && payload='{}'
    envelope="$(printf '{"event":"%s","received_at":%s,"payload":%s}' "$1" "$(date +%s)" "$payload")"
    tmp="$dir/.tmp-$$-$RANDOM"
    printf '%s' "$envelope" > "$tmp"
    mv "$tmp" "$dir/$(date +%s)-$$-$RANDOM.json"
    [ -e "$HOME/.ampel/debug" ] && printf '%s\\n' "$envelope" >> "$HOME/.ampel/hook.log"
    exit 0

    """

    // MARK: - settings.json

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func mergeSettings() throws -> URL? {
        guard var settings = readSettings() else {
            throw InstallError.unreadableSettings
        }
        var madeBackup: URL?

        // Back up before touching anything, and only if there is something to lose.
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.bak-\(Int(Date().timeIntervalSince1970))")
            // Two installs in the same second would collide. Keep the earlier
            // backup: it is the one closer to the untouched original.
            if !FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.copyItem(at: settingsURL, to: backup)
                log.info("backed up settings to \(backup.lastPathComponent)")
            }
            madeBackup = backup
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let alreadyThere = groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .contains { $0["command"] as? String == command(for: event) }
            }
            if alreadyThere { continue }

            var group: [String: Any] = ["hooks": [["type": "command", "command": command(for: event)]]]
            if !Self.matcherless.contains(event) { group["matcher"] = "*" }
            groups.append(group)   // append, never replace: other tools' hooks survive
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        return madeBackup
    }

    enum InstallError: LocalizedError {
        case unreadableSettings
        var errorDescription: String? {
            "~/.claude/settings.json is not valid JSON. Fix or move it, then try again."
        }
    }
}
