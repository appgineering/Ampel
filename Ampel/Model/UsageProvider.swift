import Foundation
import os

/// Shells out to ccusage for the usage section. See SPEC §7.
struct UsageSnapshot: Codable, Sendable {
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
@MainActor
@Observable
final class UsageProvider {
    /// The last figures we had, shown immediately on open. Nil only before the
    /// very first successful run on this machine.
    private(set) var snapshot: UsageSnapshot?
    /// True while ccusage is running behind an already-displayed snapshot.
    private(set) var isRefreshing = false
    private(set) var failed = false

    @ObservationIgnored private let log = Log("usage")
    @ObservationIgnored private let cacheLifetime: TimeInterval = 60
    @ObservationIgnored private var lastFetched: Date?
    /// The argv prefix that last worked, so we stop paying for probing.
    @ObservationIgnored private var runner: [String]?
    @ObservationIgnored private var loginPath: String?


    static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/usage-cache.json")
    }

    init() {
        // Persisted, so the first open after a relaunch shows figures rather
        // than an empty loading state.
        if let data = try? Data(contentsOf: Self.cacheURL),
           let stored = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            snapshot = stored
        }
    }

    /// Called every time the menu opens. Plan usage is a local file so it is
    /// always current; ccusage is a subprocess, so it refreshes at most once a
    /// minute and never blocks what is already on screen.
    func refresh() {
        var current = snapshot ?? UsageSnapshot(todayCost: 0)
        current.plan = PlanUsage.read()?.merging(over: current.plan)
        snapshot = current

        if let lastFetched, Date().timeIntervalSince(lastFetched) < cacheLifetime { return }
        guard !isRefreshing else { return }
        isRefreshing = true

        let runner = self.runner
        let loginPath = self.loginPath
        Task.detached(priority: .utility) {
            let result = Self.runCcusage(runner: runner, loginPath: loginPath)
            await MainActor.run { self.apply(result) }
        }
    }

    private func apply(_ result: FetchResult) {
        isRefreshing = false
        runner = result.runner
        loginPath = result.loginPath

        guard var fetched = result.snapshot else {
            // Keep whatever we were showing; only report failure when there is
            // nothing at all to show.
            failed = snapshot?.plan == nil && snapshot?.blockCost == nil
            return
        }
        failed = false
        lastFetched = Date()
        fetched.plan = snapshot?.plan ?? PlanUsage.read()
        snapshot = fetched
        try? JSONEncoder().encode(fetched).write(to: Self.cacheURL, options: .atomic)
    }

    struct FetchResult: Sendable {
        var snapshot: UsageSnapshot?
        var runner: [String]?
        var loginPath: String?
    }

    /// Runs off the main actor. Everything below is pure subprocess work.
    private nonisolated static func runCcusage(runner: [String]?, loginPath: String?) -> FetchResult {
        let shell = Shell(runner: runner, loginPath: loginPath)
        guard let blocks = shell.json(["blocks", "--json"]),
              let daily = shell.json(["daily", "--json"]) else {
            return FetchResult(snapshot: nil, runner: shell.runner, loginPath: shell.loginPath)
        }
        return FetchResult(snapshot: parse(blocks: blocks, daily: daily),
                           runner: shell.runner, loginPath: shell.loginPath)
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

/// Fresh instances rather than shared ones: parsing runs off the main actor,
/// and ISO8601DateFormatter is not safe to share across threads. A handful of
/// allocations per refresh is not worth a lock.
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static var plain: ISO8601DateFormatter { ISO8601DateFormatter() }

    /// ccusage keys daily rows by local calendar day.
    static var day: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }
}

/// The ccusage subprocess work, deliberately outside the main actor. Holds the
/// resolved runner and PATH so a refresh hands them back for reuse.
private final class Shell {
    /// Resolution order per SPEC §7.
    static let candidates = [["ccusage"], ["bunx", "ccusage"], ["npx", "-y", "ccusage"]]

    var runner: [String]?
    var loginPath: String?
    private let timeout: TimeInterval = 10
    private let log = Log("usage")

    init(runner: [String]?, loginPath: String?) {
        self.runner = runner
        self.loginPath = loginPath
    }

    func json(_ args: [String]) -> [String: Any]? {
        for candidate in runner.map({ [$0] }) ?? Shell.candidates {
            guard let data = run(candidate + args) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.error("\(candidate.joined(separator: " ")) produced unparseable output")
                continue
            }
            runner = candidate
            return object
        }
        runner = nil
        return nil
    }

    func run(_ argv: [String]) -> Data? {
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
            log.debug("cannot run \(argv.joined(separator: " "))")
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
            log.debug("\(argv.joined(separator: " ")) exited \(process.terminationStatus)")
            return nil
        }
        return data
    }

    /// A GUI app inherits a bare PATH, so node, bun and Homebrew binaries are
    /// all invisible. Ask the login shell once for the real one.
    func shellPath() -> String {
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

}
