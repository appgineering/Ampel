import AppKit
import XCTest
@testable import Ampel

/// Settings persistence, the icon renderer, logging and the diagnostics report.
final class AppSurfaceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "ampel-surface-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: - Settings

    @MainActor
    func testDefaultsMatchWhatTheAppShippedWith() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.iconStyle, .dot)
        XCTAssertEqual(settings.usageStyle, .bars)
        XCTAssertTrue(settings.pulseOnAttention)
        XCTAssertTrue(settings.notifyOnAttention)
        XCTAssertFalse(settings.hasOnboarded, "a fresh install must see the setup guide")
    }

    @MainActor
    func testEverySettingSurvivesARelaunch() {
        let settings = Settings(defaults: defaults)
        settings.iconStyle = .bars
        settings.usageStyle = .text
        settings.pulseOnAttention = false
        settings.notifyOnAttention = false
        settings.hasOnboarded = true

        let reopened = Settings(defaults: defaults)
        XCTAssertEqual(reopened.iconStyle, .bars)
        XCTAssertEqual(reopened.usageStyle, .text)
        XCTAssertFalse(reopened.pulseOnAttention)
        XCTAssertFalse(reopened.notifyOnAttention)
        XCTAssertTrue(reopened.hasOnboarded)
    }

    @MainActor
    func testUnknownStoredValuesFallBackRatherThanBreaking() {
        defaults.set("nonsense", forKey: "iconStyle")
        defaults.set("nonsense", forKey: "usageStyle")
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.iconStyle, .dot)
        XCTAssertEqual(settings.usageStyle, .bars)
    }

    // MARK: - Icon

    /// Every style must draw something for every state. A style that renders
    /// blank is invisible in the menu bar and impossible to notice in review.
    func testEveryStyleDrawsSomethingForEveryState() throws {
        let contexts: [IconContext] = [
            IconContext(aggregate: .off),
            IconContext(aggregate: .idle, sessionColors: [.systemGreen], progress: 0.2),
            IconContext(aggregate: .working, sessionColors: [.systemYellow, .systemGreen],
                        progress: 0.5),
            IconContext(aggregate: .attention,
                        sessionColors: [.systemRed, .systemYellow], progress: 0.9,
                        attentionCount: 2),
        ]
        for style in IconStyle.allCases {
            for context in contexts {
                let image = StatusIcon.image(style, context)
                XCTAssertEqual(image.size, StatusIcon.size, "\(style)")
                XCTAssertFalse(image.isTemplate,
                               "\(style) must not be a template, or the colour is tinted away")
                XCTAssertTrue(try opaquePixels(image) > 0,
                              "\(style) drew nothing for \(context.aggregate)")
            }
        }
    }

    func testBarsAndBadgeCopeWithNoSessions() throws {
        for style in [IconStyle.bars, .badge] {
            let image = StatusIcon.image(style, IconContext(aggregate: .off))
            XCTAssertTrue(try opaquePixels(image) > 0, "\(style) with no sessions drew nothing")
        }
    }

    func testEveryStyleIsDescribed() {
        for style in IconStyle.allCases {
            XCTAssertFalse(style.label.isEmpty, "\(style)")
            XCTAssertFalse(style.detail.isEmpty, "\(style)")
        }
    }

    private func opaquePixels(_ image: NSImage) throws -> Int {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                count += 1
            }
        }
        return count
    }

    // MARK: - Logging and diagnostics

    func testLogWritesLinesAPersonCanRead() throws {
        let log = Log("testcat")
        let marker = UUID().uuidString
        log.error("boom \(marker)")

        let deadline = Date().addingTimeInterval(2)
        var contents = ""
        while Date() < deadline {
            contents = (try? String(contentsOf: Log.fileURL, encoding: .utf8)) ?? ""
            if contents.contains(marker) { break }
            usleep(50_000)
        }
        XCTAssertTrue(contents.contains("ERROR [testcat] boom \(marker)"),
                      "the log must name the level and category")
    }

    func testDiagnosticsReportCarriesWhatABugReportNeeds() {
        let report = Diagnostics.report()
        for section in ["== Setup ==", "== ~/.ampel ==", "== Preferences ==",
                        "== Recent log ==", "== Crash reports =="] {
            XCTAssertTrue(report.contains(section), "missing \(section)")
        }
        XCTAssertTrue(report.contains("macOS"))
        XCTAssertTrue(report.contains("hooks installed:"))
    }
}
