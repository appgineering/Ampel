import Foundation
import os

/// First-run setup. See SPEC §8.
/// Checks that ~/.ampel/bin/ampel-hook exists and is executable and that all
/// eight hook entries are present in ~/.claude/settings.json.
/// install(): backup settings.json as settings.json.bak-<epoch>, write the
/// script, MERGE the hooks block — preserve unrelated settings and append to
/// (never replace) existing hooks on the same events.
final class HookInstaller {
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "installer")

    var isInstalled: Bool {
        // TODO(M5): implement the check.
        false
    }

    func install() throws {
        // TODO(M5): implement per SPEC §8. Script content lives in SPEC §2.1.
    }
}
