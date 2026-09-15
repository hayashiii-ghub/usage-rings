import Foundation
import Testing
import UsageCore

struct GrokBotUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func readsWeeklyRemainingAndFractionalReset() throws {
        let data = Data(#"{"usagePercent":12.942227,"nextResetTimestampUtc":"2027-02-01T04:03:33.761Z","hasNonZeroIncludedLimit":true}"#.utf8)
        let usage = try UsageResponseParser.grokBot(data, now: now)
        #expect(usage.service == .grokBot)
        #expect(abs((usage.remainingPercent(at: now) ?? 0) - 87.057773) < 0.000001)
        let reset = try #require(usage.headline?.resetsAt)
        #expect(abs(reset.timeIntervalSince1970 - 1_801_454_613.761) < 0.001)
        #expect(usage.remainingPercent(at: reset) == nil)
    }

    @Test func exhaustedAllowanceIsZeroRemaining() throws {
        let data = Data(#"{"usagePercent":100,"nextResetTimestampUtc":"2027-02-01T04:03:33Z","hasNonZeroIncludedLimit":true,"hasAvailableUsage":false}"#.utf8)
        let usage = try UsageResponseParser.grokBot(data, now: now)
        #expect(usage.remainingPercent(at: now) == 0)
    }

    @Test func missingInvalidAndPooledValuesAreUnavailable() throws {
        for raw in [
            #"{}"#,
            #"{"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"2027-02-01T04:03:33Z"}"#,
            #"{"usagePercent":-1,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"2027-02-01T04:03:33Z"}"#,
            #"{"usagePercent":10,"hasNonZeroIncludedLimit":true,"nextResetTimestampUtc":"invalid"}"#,
            #"{"usagePercent":10,"hasNonZeroIncludedLimit":true}"#,
            #"{"usagePercent":10,"nextResetTimestampUtc":"2027-02-01T04:03:33Z"}"#,
            #"{"usagePercent":10,"hasNonZeroIncludedLimit":true,"usesPooledEnterpriseAllowance":true,"nextResetTimestampUtc":"2027-02-01T04:03:33Z"}"#
        ] {
            #expect(throws: (any Error).self) { try UsageResponseParser.grokBot(Data(raw.utf8), now: now) }
        }
    }

    @Test func grokSnapshotRoundTripsThroughWidgetBridge() throws {
        let usage = ServiceUsage(service: .grokBot, state: .ready,
                                 windows: [UsageWindow(id: "week", title: "Week", usedPercent: 13, resetsAt: nil)], updatedAt: now)
        let snapshot = UsageSnapshot(services: [usage])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data) == snapshot)
    }
}
