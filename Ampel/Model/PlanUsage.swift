import Foundation

/// Real Claude plan limits, as reported by Claude Code itself on the statusLine
/// hook's stdin. Unlike ccusage's dollar estimates, these are the same numbers
/// the /usage screen shows. Only present for Pro and Max subscribers, and only
/// after a session's first API response.
struct PlanUsage: Equatable {
    struct Window: Equatable {
        var usedPercentage: Double
        var resetsAt: Date?
    }

    var fiveHour: Window?
    var sevenDay: Window?
    var spendLimit: Window?
    /// When Claude Code last wrote these, so a stale file can be labelled.
    var capturedAt: Date

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil && spendLimit == nil }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/usage.json")
    }

    /// Claude Code drops a window once it resets, and each may be absent
    /// independently, so every field here is optional by design.
    static func read(from url: URL = fileURL) -> PlanUsage? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        return parse(root, capturedAt: modified)
    }

    static func parse(_ root: [String: Any], capturedAt: Date) -> PlanUsage? {
        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        func window(_ key: String) -> Window? {
            guard let raw = limits[key] as? [String: Any],
                  let used = raw["used_percentage"] as? Double else { return nil }
            let resets = (raw["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return Window(usedPercentage: used, resetsAt: resets)
        }
        let usage = PlanUsage(fiveHour: window("five_hour"),
                              sevenDay: window("seven_day"),
                              spendLimit: window("spend_limit"),
                              capturedAt: capturedAt)
        return usage.isEmpty ? nil : usage
    }
}
