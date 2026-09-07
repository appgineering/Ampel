import XCTest
@testable import Ampel

/// Installing must never cost the user their existing configuration, and must
/// cope with ~/.ampel being deleted underneath it.
final class InstallerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ampel-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }

    private func settings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: try Data(contentsOf: settingsURL)) as? [String: Any])
    }

    private func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    private func ampelGroups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return (hooks[event] as? [[String: Any]] ?? []).filter { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).contains {
                ($0["command"] as? String)?.contains("ampel-hook") == true
            }
        }
    }

    private func backups() throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.hasPrefix("settings.json.bak-") }
    }

    // MARK: - Hooks

    func testInstallsOnAMachineWithNoClaudeDirectory() throws {
        let installer = HookInstaller(home: home)
        XCTAssertFalse(installer.isInstalled)
        try installer.install()
        XCTAssertTrue(installer.isInstalled)

        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: home.appendingPathComponent(".ampel/bin/ampel-hook").path))
        XCTAssertEqual(try backups(), [], "nothing to back up when there was no file")

        let settings = try settings()
        for event in HookInstaller.events {
            XCTAssertEqual(ampelGroups(settings, event).count, 1, event)
        }
    }

    func testPreservesUnrelatedSettingsAndForeignHooks() throws {
        try writeSettings("""
        {"model":"opus","permissions":{"allow":["Bash"]},
         "hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/tool stop"}]}],
                  "PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"/other compact"}]}]}}
        """)
        let before = try settings()
        try HookInstaller(home: home).install()
        let after = try settings()

        for (key, value) in before where key != "hooks" {
            XCTAssertTrue(NSDictionary(dictionary: ["v": value]).isEqual(to: ["v": after[key]!]),
                          "setting \(key) was altered")
        }
        let oldHooks = before["hooks"] as! [String: Any]
        let newHooks = after["hooks"] as! [String: Any]
        for (event, groups) in oldHooks {
            let new = newHooks[event] as! [[String: Any]]
            for group in groups as! [[String: Any]] {
                XCTAssertTrue(new.contains { NSDictionary(dictionary: $0).isEqual(to: group) },
                              "a hook belonging to another tool was lost on \(event)")
            }
        }
        XCTAssertEqual((newHooks["Stop"] as! [[String: Any]]).count, 2)
        XCTAssertEqual((newHooks["PreCompact"] as! [[String: Any]]).count, 1, "untouched event")
    }

    func testBackupIsTheUntouchedOriginal() throws {
        try writeSettings(#"{"model":"opus","hooks":{}}"#)
        let before = try settings()
        try HookInstaller(home: home).install()

        let names = try backups()
        XCTAssertEqual(names.count, 1)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(
            contentsOf: home.appendingPathComponent(".claude/\(names[0])"))) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: restored).isEqual(to: before))
    }

    func testReinstallDoesNotDuplicate() throws {
        let installer = HookInstaller(home: home)
        try installer.install()
        try installer.install()
        let settings = try settings()
        for event in HookInstaller.events {
            XCTAssertEqual(ampelGroups(settings, event).count, 1, event)
        }
    }

    func testMatcherOnlyWhereTheEventSupportsOne() throws {
        try HookInstaller(home: home).install()
        let hooks = try XCTUnwrap(try settings()["hooks"] as? [String: Any])
        for event in ["UserPromptSubmit", "Stop"] {
            let group = (hooks[event] as! [[String: Any]])[0]
            XCTAssertNil(group["matcher"], "\(event) takes no matcher")
        }
        for event in ["SessionStart", "PreToolUse", "Notification", "SessionEnd"] {
            let group = (hooks[event] as! [[String: Any]])[0]
            XCTAssertEqual(group["matcher"] as? String, "*", event)
        }
    }

    /// settings.json outlives ~/.ampel. Deleting the folder leaves Claude Code
    /// calling a script that is gone, and every hook then fails silently.
    func testRepairsAHookScriptDeletedUnderneathIt() throws {
        let installer = HookInstaller(home: home)
        try installer.install()
        try FileManager.default.removeItem(at: home.appendingPathComponent(".ampel"))
        XCTAssertFalse(installer.isInstalled, "a missing script is not installed")

        installer.repairIfNeeded()
        XCTAssertTrue(installer.isInstalled)
    }

    func testDoesNotWriteAScriptNobodyAskedFor() throws {
        HookInstaller(home: home).repairIfNeeded()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".ampel/bin/ampel-hook").path),
            "with no hooks registered there is nothing to repair")
    }

    // MARK: - Statusline

    private func statuslineInstaller() -> StatuslineInstaller {
        StatuslineInstaller(home: home,
                            defaults: UserDefaults(suiteName: "ampel-test-\(UUID().uuidString)")!)
    }

    func testChainsOntoAnExistingStatusline() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"/usr/local/bin/mine"}}"#)
        let installer = statuslineInstaller()
        try installer.install()

        XCTAssertTrue(installer.isInstalled)
        let inner = try String(contentsOf: home.appendingPathComponent(".ampel/statusline-inner"),
                              encoding: .utf8)
        XCTAssertEqual(inner, "/usr/local/bin/mine")

        try installer.uninstall()
        let command = (try settings()["statusLine"] as? [String: Any])?["command"] as? String
        XCTAssertEqual(command, "/usr/local/bin/mine", "the original must come back")
    }

    func testUninstallRemovesTheEntryWhenThereWasNone() throws {
        try writeSettings("{}")
        let installer = statuslineInstaller()
        try installer.install()
        try installer.uninstall()
        XCTAssertNil(try settings()["statusLine"])
    }

    /// The folder held the only record of the chained command, so deleting it
    /// destroyed the user's real statusline with nothing left to say what it was.
    func testRemembersTheChainedCommandAcrossFolderDeletion() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"/usr/local/bin/mine"}}"#)
        let defaults = UserDefaults(suiteName: "ampel-test-\(UUID().uuidString)")!
        let installer = StatuslineInstaller(home: home, defaults: defaults)
        try installer.install()

        try FileManager.default.removeItem(at: home.appendingPathComponent(".ampel"))
        XCTAssertFalse(installer.isInstalled, "the settings pointer alone is not enough")

        installer.repairIfNeeded()
        XCTAssertTrue(installer.isInstalled)
        let inner = try String(contentsOf: home.appendingPathComponent(".ampel/statusline-inner"),
                              encoding: .utf8)
        XCTAssertEqual(inner, "/usr/local/bin/mine", "chained statusline was lost")
    }

    /// Reinstalling over ourselves must not treat our own wrapper as the thing
    /// to chain to, or the real statusline disappears.
    func testReinstallDoesNotChainToItself() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"/usr/local/bin/mine"}}"#)
        let defaults = UserDefaults(suiteName: "ampel-test-\(UUID().uuidString)")!
        let installer = StatuslineInstaller(home: home, defaults: defaults)
        try installer.install()
        try installer.install()

        let inner = try String(contentsOf: home.appendingPathComponent(".ampel/statusline-inner"),
                              encoding: .utf8)
        XCTAssertEqual(inner, "/usr/local/bin/mine")
        XCTAssertFalse(inner.contains("ampel-statusline"))
    }
}
