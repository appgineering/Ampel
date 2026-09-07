// Self-check for the SPEC §7 ccusage parsing. Run: ./Tests/run.sh
// Fixtures are trimmed from real `ccusage blocks --json` / `daily --json`.
import Foundation

@main enum UsageCheck {
    static func obj(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    static func main() {
        let today = { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
                      f.timeZone = .current; return f.string(from: Date()) }()

        let blocks = obj("""
        {"blocks":[
          {"isActive":false,"isGap":false,"costUSD":2.06,"totalTokens":2102766,"endTime":"2026-06-08T20:00:00.000Z"},
          {"isActive":true,"isGap":false,"costUSD":9.541996,"totalTokens":10570140,"endTime":"2026-09-07T16:00:00.000Z"}
        ]}
        """)
        let daily = obj("""
        {"daily":[{"period":"2026-09-06","totalCost":14.938},{"period":"\(today)","totalCost":10.0573}]}
        """)

        guard let s = UsageProvider.parse(blocks: blocks, daily: daily) else { fatalError("nil") }
        assert(s.currentBlockLine.contains("$9.54"), s.currentBlockLine)
        assert(s.currentBlockLine.contains("10.6M tokens"), s.currentBlockLine)
        assert(s.currentBlockLine.contains("resets"), s.currentBlockLine)
        assert(s.todayLine.contains("$10.06"), s.todayLine)

        // No active block, and a day ccusage has no row for.
        let quiet = UsageProvider.parse(blocks: obj(#"{"blocks":[{"isActive":false}]}"#),
                                        daily: obj(#"{"daily":[{"period":"1999-01-01","totalCost":3}]}"#))
        assert(quiet?.currentBlockLine == "Current block: idle", quiet?.currentBlockLine ?? "nil")
        assert(quiet?.todayLine.contains("$0.00") == true, quiet?.todayLine ?? "nil")

        // Empty and wrongly typed payloads must degrade, never crash.
        assert(UsageProvider.parse(blocks: [:], daily: [:]) != nil)
        assert(UsageProvider.parse(blocks: obj(#"{"blocks":"junk"}"#), daily: obj(#"{"daily":7}"#)) != nil)

        print("UsageCheck: all assertions passed")
    }
}
