import Foundation
import os

/// Shells out to ccusage for the usage section. See SPEC §7.
struct UsageSnapshot {
    var blockCost: Double?
    var blockTokens: Int?
    /// How far through the rate limit window we are, 0...1. The window has a
    /// fixed length, which is the only denominator here that is not invented.
    var blockProgress: Double?
    var blockResets: Date?
    var todayCost: Double
    /// Real plan limits when Claude Code is feeding them to us.
    var plan: PlanUsage?

    /// The busiest of the last seven days, used to scale today's bar. Recent
    /// rather than all time: an outlier from months ago makes every normal day
    /// look like nothing.
    var todayPeak: Double?

    /// Without the reset time, which the bar shows as its own caption.
    var blockLabel: String {
        guard let blockCost else { return "Current block: idle" }
        var parts = ["Current block: \(UsageProvider.money(blockCost))"]
        if let blockTokens { parts.append("\(UsageProvider.compact(blockTokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    var currentBlockLine: String {
        guard let blockResets else { return blockLabel }
        return blockLabel + " · resets \(blockResets.formatted(.dateTime.hour().minute()))"
    }

    var todayLine: String { "Today: \(UsageProvider.money(todayCost))" }

    /// Today measured against the busiest day ccusage knows about.
    var todayProgress: Double? {
        guard let todayPeak, todayPeak > 0 else { return nil }
        return min(todayCost / todayPeak, 1)
    }
}

/// Resolution order: `ccusage` on PATH, then `bunx ccusage`, then `npx -y ccusage`.
/// Runs off the main thread with a 10s timeout and a 60s cache. Any failure
/// yields nil and the menu falls back to a static line; it never blocks.
actor UsageProvider {
    private let log = Logger(subsystem: "com.appgineering.ampel", category: "usage")
    private let timeout: TimeInterval = 10
    private let cacheLifetime: TimeInterval = 60

    private var cached: UsageSnapshot?
    private var cachedAt: Date?
    /// The argv prefix that last worked, so we stop paying for probing.
    private var runner: [String]?
    private var loginPath: String?

    private static let candidates = [["ccusage"], ["bunx", "ccusage"], ["npx", "-y", "ccusage"]]

    func fetch() async -> UsageSnapshot? {
        // Plan usage is a local file write by Claude Code, so it is always
        // read fresh; only the ccusage subprocesses are worth caching.
        let plan = PlanUsage.read()
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            var snapshot = cached
            snapshot.plan = plan
            return snapshot
        }
        guard let blocks = json(["blocks", "--json"]), let daily = json(["daily", "--json"]) else {
            // Plan usage alone is still worth showing.
            return plan.map { UsageSnapshot(todayCost: 0, plan: $0) }
        }
        guard var snapshot = Self.parse(blocks: blocks, daily: daily) else {
            log.error("ccusage ran but its output did not parse")
            return nil
        }
        snapshot.plan = plan
        cached = snapshot
        cachedAt = Date()
        return snapshot
    }

    // MARK: - ccusage invocation

    private func json(_ args: [String]) -> [String: Any]? {
        for candidate in runner.map({ [$0] }) ?? Self.candidates {
            guard let data = run(candidate + args) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.error("\(candidate.joined(separator: " "), privacy: .public) produced unparseable output")
                continue
            }
            runner = candidate
            return object
        }
        runner = nil
        return nil
    }

    private func run(_ argv: [String]) -> Data? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = shellPath()
        process.environment = environment

        do { try process.run() } catch {
            log.debug("cannot run \(argv.joined(separator: " "), privacy: .public)")
            return nil
        }

        // A launched-from-Finder app has no terminal to be killed with, so the
        // timeout is the only thing standing between a wedged ccusage and a
        // permanently empty usage section.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        deadline.cancel()

        guard process.terminationStatus == 0 else {
            log.debug("\(argv.joined(separator: " "), privacy: .public) exited \(process.terminationStatus)")
            return nil
        }
        return data
    }

    /// A GUI app inherits a bare PATH, so node, bun and Homebrew binaries are
    /// all invisible. Ask the login shell once for the real one.
    private func shellPath() -> String {
        if let loginPath { return loginPath }
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "printf %s \"$PATH\""]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return fallback }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        loginPath = path.isEmpty ? fallback : path
        return loginPath ?? fallback
    }

    // MARK: - Parsing

    /// Field names follow the real ccusage output, which differs from the
    /// illustrative shapes in SPEC §7: blocks carry `costUSD`/`totalTokens`/
    /// `endTime`, and daily rows are keyed by `period` with `totalCost`.
    nonisolated static func parse(blocks: [String: Any], daily: [String: Any]) -> UsageSnapshot? {
        let blockRows = blocks["blocks"] as? [[String: Any]] ?? []
        let active = blockRows.first { $0["isActive"] as? Bool == true }

        let resets = (active?["endTime"] as? String).flatMap(date(from:))
        let started = (active?["startTime"] as? String).flatMap(date(from:))
        var progress: Double?
        if let started, let resets, resets > started {
            let span = resets.timeIntervalSince(started)
            progress = min(max(Date().timeIntervalSince(started) / span, 0), 1)
        }

        let dailyRows = daily["daily"] as? [[String: Any]] ?? []
        let today = ISO8601DateFormatter.day.string(from: Date())
        let todayCost = dailyRows.first { $0["period"] as? String == today }?["totalCost"] as? Double ?? 0
        let peak = dailyRows.suffix(7).compactMap { $0["totalCost"] as? Double }.max()

        return UsageSnapshot(
            blockCost: active?["costUSD"] as? Double,
            blockTokens: active?["totalTokens"] as? Int,
            blockProgress: progress,
            blockResets: resets,
            todayCost: todayCost,
            todayPeak: peak)
    }

    nonisolated static func date(from iso: String) -> Date? {
        ISO8601DateFormatter.fractional.date(from: iso) ?? ISO8601DateFormatter.plain.date(from: iso)
    }

    private nonisolated static let en = Locale(identifier: "en_US")

    nonisolated static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(en))
    }

    nonisolated static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(en))
    }

    nonisolated static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(en))
    }

}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain = ISO8601DateFormatter()
    /// ccusage keys daily rows by local calendar day.
    static let day: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}
