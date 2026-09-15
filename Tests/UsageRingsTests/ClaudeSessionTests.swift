import Foundation
import Testing
@testable import UsageRings

struct ClaudeSessionTests {
    @Test func missingOrInvalidFileFailsWithoutUsingTheSystemKeychain() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: (any Error).self) { try UsageCredentialReader.claude(home: home) }
        let folder = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: folder.appendingPathComponent(".credentials.json"))
        #expect(throws: (any Error).self) { try UsageCredentialReader.claude(home: home) }
    }

    @Test func expiredFileDoesNotFallBackToTheSystemKeychain() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = folder.appendingPathComponent(".credentials.json")
        func session(expiry: Date) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["claudeAiOauth": [
                "accessToken": "synthetic-session",
                "expiresAt": expiry.timeIntervalSince1970 * 1000,
                "scopes": ["user:profile"]
            ]])
        }
        try session(expiry: Date().addingTimeInterval(-60)).write(to: file)
        for _ in 0..<3 {
            #expect(throws: (any Error).self) { try UsageCredentialReader.claude(home: home) }
        }
        try session(expiry: Date().addingTimeInterval(600)).write(to: file)
        #expect(try UsageCredentialReader.claude(home: home) == "synthetic-session")
    }
}
