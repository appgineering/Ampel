import Foundation

/// Decides when a plan limit is worth a notification: once each time a window
/// climbs past the threshold, and again only after it has dropped back under,
/// which in practice means after it reset.
struct UsageWarning {
    // ponytail: one fixed threshold. Make it a setting if 80 suits nobody.
    static let threshold = 80.0

    // ponytail: in memory, so relaunching above the threshold warns once more.
    private var warned: Set<String> = []

    /// The notification bodies due for this reading, usually none.
    mutating func check(_ plan: PlanUsage?, now: Date = Date()) -> [String] {
        var due: [String] = []
        for (name, window) in [("5-hour limit", plan?.fiveHour), ("7-day limit", plan?.sevenDay)] {
            // usage.json is only rewritten while a session is open, so a window
            // whose reset has passed is an old reading, not a live one.
            guard let window, window.usedPercentage >= Self.threshold,
                  window.resetsAt.map({ $0 > now }) ?? true else {
                warned.remove(name)
                continue
            }
            guard warned.insert(name).inserted else { continue }
            let resets = window.resetsAt.map {
                ", resets \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
            } ?? ""
            due.append("\(name) at \(UsageProvider.percent(window.usedPercentage))\(resets)")
        }
        return due
    }
}
