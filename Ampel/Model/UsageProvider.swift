import Foundation
import os

/// Shells out to ccusage for the usage section. See SPEC §7.
struct UsageSnapshot {
    var currentBlockLine: String   // "Current block: $X.XX · N tokens · resets HH:MM"
    var todayLine: String          // "Today: $Y.YY"
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
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            return cached
        }
        guard let blocks = json(["blocks", "--json"]), let daily = json(["daily", "--json"]) else {
            return nil
        }
        guard let snapshot = Self.parse(blocks: blocks, daily: daily) else {
            log.error("ccusage ran but its output did not parse")
            return nil
        }
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

        let blockLine: String
        if let active {
            let cost = active["costUSD"] as? Double ?? 0
            let tokens = active["totalTokens"] as? Int ?? 0
            var parts = ["Current block: \(money(cost))", "\(compact(tokens)) tokens"]
            if let resets = active["endTime"] as? String, let time = clockTime(resets) {
                parts.append("resets \(time)")
            }
            blockLine = parts.joined(separator: " · ")
        } else {
            blockLine = "Current block: idle"
        }

        let today = ISO8601DateFormatter.day.string(from: Date())
        let dailyRows = daily["daily"] as? [[String: Any]] ?? []
        let cost = dailyRows.first { $0["period"] as? String == today }?["totalCost"] as? Double
        return UsageSnapshot(currentBlockLine: blockLine, todayLine: "Today: \(money(cost ?? 0))")
    }

    /// ccusage reports US dollars. Formatting these in the user's locale gives
    /// "9,54 US$" on a German Mac, so the money and token formats are pinned.
    private nonisolated static let en = Locale(identifier: "en_US")

    private nonisolated static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(en))
    }

    private nonisolated static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(en))
    }

    private nonisolated static func clockTime(_ iso: String) -> String? {
        guard let date = ISO8601DateFormatter.fractional.date(from: iso)
            ?? ISO8601DateFormatter.plain.date(from: iso) else { return nil }
        return date.formatted(.dateTime.hour().minute())
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
