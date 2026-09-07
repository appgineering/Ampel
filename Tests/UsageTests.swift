import XCTest
@testable import Ampel

/// ccusage output, plan limits, and the formatting rules that come from real
/// output rather than the illustrative shapes in the spec.
final class UsageTests: XCTestCase {
    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private var today: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    // MARK: - ccusage

    func testParsesTheActiveBlockAndToday() throws {
        let blocks = try object("""
        {"blocks":[
          {"isActive":false,"costUSD":2.06,"totalTokens":2102766,"endTime":"2026-06-08T20:00:00.000Z"},
          {"isActive":true,"costUSD":9.541996,"totalTokens":10570140,
           "startTime":"2026-09-07T11:00:00.000Z","endTime":"2026-09-07T16:00:00.000Z"}
        ]}
        """)
        let daily = try object("""
        {"daily":[{"period":"2026-09-06","totalCost":14.938},
                  {"period":"\(today)","totalCost":10.0573}]}
        """)
        let snapshot = try XCTUnwrap(UsageProvider.parse(blocks: blocks, daily: daily))

        XCTAssertEqual(snapshot.blockCost ?? 0, 9.541996, accuracy: 0.0001)
        XCTAssertEqual(snapshot.blockTokens, 10570140)
        XCTAssertTrue(snapshot.currentBlockLine.contains("$9.54"), snapshot.currentBlockLine)
        XCTAssertTrue(snapshot.currentBlockLine.contains("10.6M tokens"), snapshot.currentBlockLine)
        XCTAssertTrue(snapshot.todayLine.contains("$10.06"), snapshot.todayLine)
    }

    /// The bar label must not repeat the reset time its caption already shows.
    func testBlockLabelExcludesTheResetTime() throws {
        let blocks = try object("""
        {"blocks":[{"isActive":true,"costUSD":1,"totalTokens":10,
                    "endTime":"2026-09-07T16:00:00.000Z"}]}
        """)
        let snapshot = try XCTUnwrap(UsageProvider.parse(blocks: blocks, daily: try object("{}")))
        XCTAssertFalse(snapshot.blockLabel.contains("resets"))
        XCTAssertTrue(snapshot.currentBlockLine.contains("resets"))
    }

    /// A German locale renders US dollars as "9,54 US$", which is neither what
    /// ccusage reported nor what the spec asks for.
    func testMoneyAndTokensIgnoreTheUserLocale() {
        XCTAssertEqual(UsageProvider.money(9.541996), "$9.54")
        XCTAssertEqual(UsageProvider.compact(10570140), "10.6M")
        XCTAssertEqual(UsageProvider.percent(42), "42%")
    }

    /// An outlier from months ago makes every ordinary day look like nothing.
    func testTodayIsScaledAgainstTheLastSevenDays() throws {
        var rows = [#"{"period":"1999-01-01","totalCost":848}"#]
        rows += (1...6).map { #"{"period":"2026-09-0\#($0)","totalCost":20}"# }
        rows.append(#"{"period":"\#(today)","totalCost":10}"#)
        let daily = try object("{\"daily\":[\(rows.joined(separator: ","))]}")

        let snapshot = try XCTUnwrap(UsageProvider.parse(blocks: try object("{}"), daily: daily))
        XCTAssertEqual(snapshot.todayPeak, 20, "the ancient outlier must not set the scale")
        XCTAssertEqual(snapshot.todayProgress ?? 0, 0.5, accuracy: 0.001)
    }

    func testBlockProgressIsElapsedTimeThroughTheWindow() throws {
        let start = Date().addingTimeInterval(-3600)
        let end = Date().addingTimeInterval(3600)
        let format = ISO8601DateFormatter()
        let blocks = try object("""
        {"blocks":[{"isActive":true,"costUSD":1,"totalTokens":1,
          "startTime":"\(format.string(from: start))","endTime":"\(format.string(from: end))"}]}
        """)
        let snapshot = try XCTUnwrap(UsageProvider.parse(blocks: blocks, daily: try object("{}")))
        XCTAssertEqual(snapshot.blockProgress ?? 0, 0.5, accuracy: 0.02)
    }

    func testDegradesRatherThanCrashing() throws {
        let empty = UsageProvider.parse(blocks: try object("{}"), daily: try object("{}"))
        XCTAssertEqual(empty?.currentBlockLine, "Current block: idle")
        XCTAssertNil(empty?.blockProgress)
        XCTAssertTrue(empty?.todayLine.contains("$0.00") == true)

        let nonsense = UsageProvider.parse(blocks: try object(#"{"blocks":"junk"}"#),
                                           daily: try object(#"{"daily":7}"#))
        XCTAssertNotNil(nonsense, "wrongly typed output must not be fatal")
    }

    // MARK: - Plan limits

    func testParsesRateLimitsFromTheStatuslinePayload() throws {
        let payload = try object("""
        {"session_id":"a","rate_limits":{
          "five_hour":{"used_percentage":23.5,"resets_at":1738425600},
          "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
        """)
        let plan = try XCTUnwrap(PlanUsage.parse(payload, capturedAt: Date()))
        XCTAssertEqual(plan.fiveHour?.usedPercentage, 23.5)
        XCTAssertEqual(plan.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1738425600))
        XCTAssertEqual(plan.sevenDay?.usedPercentage, 41.2)
        XCTAssertNil(plan.spendLimit, "an absent window stays absent")
    }

    /// rate_limits is missing entirely off Pro and Max, and Claude Code drops
    /// each window once it resets.
    func testAbsentLimitsYieldNothingRatherThanZero() throws {
        XCTAssertNil(PlanUsage.parse(try object(#"{"session_id":"a"}"#), capturedAt: Date()))
        XCTAssertNil(PlanUsage.parse(try object(#"{"rate_limits":{}}"#), capturedAt: Date()))

        let partial = PlanUsage.parse(
            try object(#"{"rate_limits":{"seven_day":{"used_percentage":8}}}"#), capturedAt: Date())
        XCTAssertNil(partial?.fiveHour)
        XCTAssertEqual(partial?.sevenDay?.usedPercentage, 8)
        XCTAssertNil(partial?.sevenDay?.resetsAt, "resets_at is optional too")
    }

    func testSnapshotSurvivesEncodingForTheCache() throws {
        let blocks = try object("""
        {"blocks":[{"isActive":true,"costUSD":3.5,"totalTokens":100,
                    "endTime":"2026-09-07T16:00:00.000Z"}]}
        """)
        var snapshot = try XCTUnwrap(UsageProvider.parse(blocks: blocks, daily: try object("{}")))
        snapshot.plan = PlanUsage(fiveHour: .init(usedPercentage: 12, resetsAt: Date()),
                                  sevenDay: nil, spendLimit: nil, capturedAt: Date())

        let restored = try JSONDecoder().decode(
            UsageSnapshot.self, from: try JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.blockCost, snapshot.blockCost)
        XCTAssertEqual(restored.plan?.fiveHour?.usedPercentage, 12)
    }
}
