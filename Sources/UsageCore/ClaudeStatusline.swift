import CryptoKit
import Darwin
import Foundation

public struct ClaudeStatuslineInput: Sendable {
    public let usage: ServiceUsage
    public let responseMarker: String
}

public enum ClaudeStatusline {
    public static func parse(_ data: Data, now: Date = Date()) throws -> ClaudeStatuslineInput? {
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard let limits = input.rate_limits, let session = input.session_id, !session.isEmpty,
              let duration = input.cost?.total_api_duration_ms, duration.isFinite, duration > 0 else { return nil }
        var windows: [UsageWindow] = []
        for (id, title, window) in [("five_hour", "5 hours", limits.five_hour), ("seven_day", "Week", limits.seven_day)] {
            guard let window else { continue }
            guard window.used_percentage.isFinite, (0...100).contains(window.used_percentage),
                  window.resets_at.isFinite, window.resets_at > 0 else { throw UsageReadError.invalidResponse }
            let reset = Date(timeIntervalSince1970: window.resets_at)
            guard reset > now else { continue }
            windows.append(UsageWindow(id: id, title: title, usedPercent: window.used_percentage, resetsAt: reset))
        }
        guard !windows.isEmpty else { return nil }
        // Status lines also run for UI events. Only new API activity renews freshness.
        // Hash the session marker so no session ID or workspace metadata is stored.
        let marker = SHA256.hash(data: Data("\(session):\(duration)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return ClaudeStatuslineInput(
            usage: ServiceUsage(service: .claude, state: .ready, windows: windows, updatedAt: now),
            responseMarker: marker
        )
    }

    private struct Input: Decodable {
        let session_id: String?
        let cost: Cost?
        let rate_limits: Limits?
    }
    private struct Cost: Decodable { let total_api_duration_ms: Double? }
    private struct Limits: Decodable { let five_hour: Window?; let seven_day: Window? }
    private struct Window: Decodable { let used_percentage: Double; let resets_at: Double }
}

public struct ClaudeStatuslineCache: Codable, Equatable, Sendable {
    public var usage: ServiceUsage
    public var responseMarkers: [String]
    public let version: Int
}

public enum ClaudeStatuslineFile {
    public static func url() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Usage Rings/claude-statusline-v1.json")
    }

    public static func read(from location: URL = url()) -> ClaudeStatuslineCache? {
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536, let data = try? Data(contentsOf: location),
              let cache = try? JSONDecoder().decode(ClaudeStatuslineCache.self, from: data),
              cache.version == 1, cache.usage.service == .claude, cache.usage.state == .ready,
              cache.usage.updatedAt != nil, !cache.usage.windows.isEmpty, cache.usage.windows.count <= 2,
              Set(cache.usage.windows.map(\.id)).count == cache.usage.windows.count,
              cache.usage.windows.allSatisfy({
                  ["five_hour", "seven_day"].contains($0.id) && $0.usedPercent.isFinite &&
                  (0...100).contains($0.usedPercent) && $0.resetsAt != nil
              }), cache.responseMarkers.count <= 256 else { return nil }
        return cache
    }

    @discardableResult
    public static func write(_ input: ClaudeStatuslineInput, to location: URL = url()) throws -> ClaudeStatuslineCache {
        let folder = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(location.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw UsageReadError.requestFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw UsageReadError.requestFailed }
        defer { flock(descriptor, LOCK_UN) }
        let previous = read(from: location)
        if let previous, previous.responseMarkers.contains(input.responseMarker) { return previous }
        let markers = Array(((previous?.responseMarkers ?? []) + [input.responseMarker]).suffix(256))
        let cache = ClaudeStatuslineCache(usage: input.usage, responseMarkers: markers, version: 1)
        try JSONEncoder().encode(cache).write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return cache
    }
}
