// Self-check for the SPEC §8 first-run install. Run: ./Tests/run.sh
// Runs the real merge against throwaway homes, never the user's own.
import Foundation

@main enum InstallCheck {
    static func dict(_ url: URL) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    static func ampelGroups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.filter { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).contains {
                ($0["command"] as? String)?.contains("ampel-hook") == true
            }
        }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampel-install-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try freshMachine(root.appendingPathComponent("fresh"))
        try existingSettings(root.appendingPathComponent("existing"))
        print("InstallCheck: all assertions passed")
    }

    /// No ~/.claude at all, which is the state the definition of done starts from.
    static func freshMachine(_ home: URL) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let installer = HookInstaller(home: home)
        assert(installer.isInstalled == false)
        try installer.install()
        assert(installer.isInstalled, "install must work with no ~/.claude present")

        let script = home.appendingPathComponent(".ampel/bin/ampel-hook")
        assert(FileManager.default.isExecutableFile(atPath: script.path), "script must be executable")

        // No backup to make when there was no file to lose.
        let backups = try FileManager.default
            .contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.hasPrefix("settings.json.bak-") }
        assert(backups.isEmpty, "nothing to back up on a fresh machine, got \(backups)")

        let settings = dict(home.appendingPathComponent(".claude/settings.json"))
        for event in HookInstaller.events {
            assert(ampelGroups(settings, event).count == 1, "missing hook for \(event)")
        }
    }

    /// An existing settings.json with unrelated settings and a foreign hook on
    /// an event Ampel also wants. Nothing of it may be lost.
    static func existingSettings(_ home: URL) throws {
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let settingsURL = claude.appendingPathComponent("settings.json")
        let original = """
        {"model":"opus","permissions":{"allow":["Bash"]},
         "hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/tool stop"}]}],
                  "PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"/other/tool compact"}]}]}}
        """
        try original.write(to: settingsURL, atomically: true, encoding: .utf8)
        let before = dict(settingsURL)

        let installer = HookInstaller(home: home)
        assert(installer.isInstalled == false)
        try installer.install()
        assert(installer.isInstalled)
        let after = dict(settingsURL)

        // Unrelated top level settings survive byte for byte.
        for (key, value) in before where key != "hooks" {
            assert(after[key] != nil, "lost \(key)")
            assert(NSDictionary(dictionary: ["v": value]).isEqual(to: ["v": after[key]!]), "changed \(key)")
        }
        // Foreign hook groups survive, including on an event Ampel appends to.
        let oldHooks = before["hooks"] as! [String: Any]
        let newHooks = after["hooks"] as! [String: Any]
        for (event, groups) in oldHooks {
            let new = newHooks[event] as! [[String: Any]]
            for group in groups as! [[String: Any]] {
                assert(new.contains { NSDictionary(dictionary: $0).isEqual(to: group) },
                       "lost a foreign hook group on \(event)")
            }
        }
        assert((newHooks["Stop"] as! [[String: Any]]).count == 2, "Stop must have both hooks")
        assert((newHooks["PreCompact"] as! [[String: Any]]).count == 1, "PreCompact untouched")

        // Exactly one timestamped backup, and it still parses as the original.
        let backups = try FileManager.default.contentsOfDirectory(atPath: claude.path)
            .filter { $0.hasPrefix("settings.json.bak-") }
        assert(backups.count == 1, "expected one backup, got \(backups)")
        let restored = dict(claude.appendingPathComponent(backups[0]))
        assert(NSDictionary(dictionary: restored).isEqual(to: before), "backup is not the original")

        // Installing again must not duplicate entries.
        try installer.install()
        let twice = dict(settingsURL)
        for event in HookInstaller.events {
            assert(ampelGroups(twice, event).count == 1, "\(event) duplicated on reinstall")
        }
    }
}
