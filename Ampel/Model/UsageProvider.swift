import Foundation
import os

/// Shells out to ccusage for the usage section. See SPEC §7.
/// Resolution order: `ccusage` on PATH, then `bunx ccusage`, then `npx -y ccusage`.
/// Runs via Process off the main thread, 10s timeout, 60s cache.
/// On any failure: usable fallback text, never block the menu.
struct UsageSnapshot {
    var currentBlockLine: String   // "Current block: $X.XX · N tokens · resets HH:MM"
    var todayLine: String          // "Today: $Y.YY"
}

final class UsageProvider {
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "usage")

    func fetch() async -> UsageSnapshot? {
        // TODO(M4): run `ccusage blocks --json` and `ccusage daily --json`,
        // parse the active block and today's totals, cache for 60s.
        nil
    }
}
