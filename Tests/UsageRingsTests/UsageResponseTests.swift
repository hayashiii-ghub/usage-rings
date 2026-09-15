import UsageCore
import Foundation
import Testing
@testable import UsageRings

struct UsageResponseTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func codexWeeklyOnlyPrimaryIsNotCalledFiveHours() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":54,"limit_window_seconds":604800,"reset_at":1800003600},"secondary_window":null}}"#.utf8)
        let usage = try UsageResponseParser.codex(data, now: now)
        #expect(usage.windows.count == 1)
        #expect(usage.headline?.title == "Week")
        #expect(usage.remainingPercent(at: now) == 46)
    }

    @Test func codexShowsTheMostConstrainedWindow() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000},"secondary_window":{"used_percent":82,"limit_window_seconds":604800}}}"#.utf8)
        let usage = try UsageResponseParser.codex(data, now: now)
        #expect(usage.headline?.title == "Week")
        #expect(usage.remainingPercent(at: now) == 18)
    }

    @Test func cursorUsesReportedPercentageInsteadOfDollarAllowance() throws {
        let data = Data(#"{"billingCycleEnd":"2027-02-01T12:00:00.000Z","individualUsage":{"plan":{"enabled":true,"used":2000,"limit":2000,"remaining":0,"totalPercentUsed":58.9,"autoPercentUsed":58.93,"apiPercentUsed":58.58}}}"#.utf8)
        let usage = try UsageResponseParser.cursor(data, now: now)
        #expect(abs((usage.headline?.remainingPercent ?? 0) - 41.1) < 0.001)
        #expect(usage.windows.count == 3)
        #expect(usage.headline?.resetsAt != nil)
    }

    @Test func fractionalPercentageIsNotMultipliedByOneHundred() throws {
        let data = Data(#"{"individualUsage":{"plan":{"totalPercentUsed":0.36}}}"#.utf8)
        let usage = try UsageResponseParser.cursor(data, now: now)
        #expect(usage.headline?.remainingPercent == 99.64)
    }

    @Test func missingPercentageDoesNotBecomeAFullRing() {
        let data = Data(#"{"individualUsage":{"plan":{"used":0,"limit":2000}}}"#.utf8)
        #expect(throws: (any Error).self) { try UsageResponseParser.cursor(data) }
        #expect(throws: (any Error).self) { try UsageResponseParser.codex(Data(#"{"rate_limit":{}}"#.utf8)) }
    }

    @Test func invalidNegativeUsageIsRejected() {
        #expect(throws: (any Error).self) {
            try UsageResponseParser.cursor(Data(#"{"individualUsage":{"plan":{"totalPercentUsed":-5}}}"#.utf8))
        }
    }

    @Test func exhaustedAllowanceStaysZeroRatherThanWrapping() throws {
        let usage = try UsageResponseParser.cursor(Data(#"{"individualUsage":{"plan":{"totalPercentUsed":105}}}"#.utf8), now: now)
        #expect(usage.remainingPercent(at: now) == 0)
    }

    @Test func passedResetAndOldReadingAreUnknown() {
        let usage = ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "week", title: "Week", usedPercent: 80, resetsAt: now.addingTimeInterval(60))
        ], updatedAt: now)
        #expect(usage.remainingPercent(at: now) == 20)
        #expect(usage.remainingPercent(at: now.addingTimeInterval(60)) == nil)
        let noReset = ServiceUsage(service: .cursor, state: .ready, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 40, resetsAt: nil)
        ], updatedAt: now)
        #expect(noReset.remainingPercent(at: now.addingTimeInterval(UsageSnapshot.maximumAge)) == nil)
    }

    @Test func failedRefreshNeverDisplaysOldDataAsCurrent() {
        let usage = ServiceUsage(service: .cursor, state: .unavailable, windows: [
            UsageWindow(id: "total", title: "This month", usedPercent: 40, resetsAt: nil)
        ], updatedAt: now)
        #expect(usage.remainingPercent(at: now) == nil)
    }

    @Test func timelineStillExpiresWhenTheSystemDefersItsRequestedReload() {
        let expiry = now.addingTimeInterval(UsageSnapshot.maximumAge)
        let reset = now.addingTimeInterval(60)
        let snapshot = UsageSnapshot(services: [ServiceUsage(service: .codex, state: .ready, windows: [
            UsageWindow(id: "primary", title: "5 hours", usedPercent: 20, resetsAt: reset)
        ], updatedAt: now)])
        #expect(snapshot.validityBoundaries(after: now) == [reset, expiry])
        #expect(snapshot.validityBoundaries(after: now.addingTimeInterval(900)).contains(expiry))
    }

    @Test func widgetSnapshotRoundTripsWithoutCredentials() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        try UsageSnapshotFile.write(.empty, to: url)
        #expect(UsageSnapshotFile.read(from: url) == .empty)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("token"))
        #expect(!text.contains("account"))
        try Data("broken".utf8).write(to: url)
        #expect(UsageSnapshotFile.read(from: url) == .empty)
    }

    @Test func cursorUTF16TokenIsDecodedWithoutNullCharacters() {
        let token = "test.payload.signature"
        #expect(UsageCredentialReader.decodeToken(token.data(using: .utf16LittleEndian)!) == token)
        #expect(UsageCredentialReader.decodeToken(Data(token.utf8)) == token)
    }

    @Test func cursorExpiredSessionIsRejectedWithoutRefresh() throws {
        let token = jwt(subject: "auth0|user_test", expiry: now.timeIntervalSince1970 - 1)
        #expect(throws: (any Error).self) { try UsageCredentialReader.cursorCookie(token: token, now: now) }
        let valid = jwt(subject: "auth0|user_test", expiry: now.timeIntervalSince1970 + 600)
        #expect(try UsageCredentialReader.cursorCookie(token: valid, now: now) == "WorkosCursorSessionToken=user_test%3A%3A\(valid)")
        let malformed = jwt(subject: "user_test; injected=bad", expiry: now.timeIntervalSince1970 + 600)
        #expect(throws: (any Error).self) { try UsageCredentialReader.cursorCookie(token: malformed, now: now) }
    }

    @Test func bridgeOnlyAcceptsItsReadOnlyLocalRequest() {
        let valid = "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:\(UsageSnapshot.bridgePort)\r\nX-Usage-Rings-Widget: 1\r\n\r\n"
        #expect(UsageSnapshotServer.accepts(Data(valid.utf8)))
        for invalid in [
            valid.replacingOccurrences(of: "GET", with: "POST"),
            valid.replacingOccurrences(of: "/v1/usage", with: "/credentials"),
            valid.replacingOccurrences(of: "127.0.0.1", with: "example.com"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 0"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 1\r\nOrigin: https://example.com"),
            valid.replacingOccurrences(of: "X-Usage-Rings-Widget: 1", with: "X-Usage-Rings-Widget: 1\r\nX-Usage-Rings-Widget: 1")
        ] { #expect(!UsageSnapshotServer.accepts(Data(invalid.utf8))) }
    }

    private func jwt(subject: String, expiry: Double) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["sub": subject, "exp": expiry])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "test.\(payload).signature"
    }
}
