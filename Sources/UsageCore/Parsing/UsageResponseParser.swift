import Foundation

public enum UsageReadError: Error {
    case missingSession, expiredSession, invalidResponse, requestFailed
}

public enum UsageResponseParser {
    public static func codex(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(CodexResponse.self, from: data)
        guard let limits = response.rateLimit else { throw UsageReadError.invalidResponse }
        let pairs = [("primary", limits.primaryWindow), ("secondary", limits.secondaryWindow)]
        let windows = try pairs.compactMap { id, raw -> UsageWindow? in
            guard let raw else { return nil }
            let title: String
            switch raw.limitWindowSeconds {
            case 18_000: title = "5 hours"
            case 604_800: title = "Week"
            case let seconds? where seconds > 0 && seconds % 86_400 == 0: title = "\(seconds / 86_400) days"
            case let seconds? where seconds > 0 && seconds % 3_600 == 0: title = "\(seconds / 3_600) hours"
            default: title = id == "primary" ? "Current window" : "Other window"
            }
            return UsageWindow(id: id, title: title, usedPercent: try percent(raw.usedPercent),
                               resetsAt: raw.resetAt.map { Date(timeIntervalSince1970: $0) })
        }
        guard !windows.isEmpty else { throw UsageReadError.invalidResponse }
        return ServiceUsage(service: .codex, state: .ready, windows: windows, updatedAt: now)
    }

    public static func cursor(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(CursorResponse.self, from: data)
        guard let plan = response.individualUsage?.plan, plan.enabled != false,
              let total = plan.totalPercentUsed else { throw UsageReadError.invalidResponse }
        let reset = response.billingCycleEnd.flatMap(parseDate)
        var windows = [UsageWindow(id: "total", title: "This month", usedPercent: try percent(total), resetsAt: reset)]
        for (id, title, value) in [("cursor", "Cursor models", plan.autoPercentUsed), ("other", "Other models", plan.apiPercentUsed)] {
            if let value {
                windows.append(UsageWindow(id: id, title: title, usedPercent: try percent(value), resetsAt: reset))
            }
        }
        return ServiceUsage(service: .cursor, state: .ready, windows: windows, updatedAt: now)
    }

    public static func grokBot(_ data: Data, now: Date = Date()) throws -> ServiceUsage {
        let response = try JSONDecoder().decode(GrokBotResponse.self, from: data)
        guard response.usesPooledEnterpriseAllowance != true,
              response.hasNonZeroIncludedLimit == true,
              let used = response.usagePercent,
              let timestamp = response.nextResetTimestampUtc,
              let reset = parseDate(timestamp) else { throw UsageReadError.invalidResponse }
        let window = UsageWindow(id: "week", title: "Week", usedPercent: try percent(used), resetsAt: reset)
        return ServiceUsage(service: .grokBot, state: .ready, windows: [window], updatedAt: now)
    }

    private static func percent(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw UsageReadError.invalidResponse }
        return min(value, 100)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct GrokBotResponse: Decodable {
    let usagePercent: Double?
    let nextResetTimestampUtc: String?
    let hasNonZeroIncludedLimit: Bool?
    let usesPooledEnterpriseAllowance: Bool?
}

private struct CodexResponse: Decodable {
    let rateLimit: Limits?
    enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit" }
    struct Limits: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window", secondaryWindow = "secondary_window"
        }
    }
    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent", limitWindowSeconds = "limit_window_seconds", resetAt = "reset_at"
        }
    }
}

private struct CursorResponse: Decodable {
    let billingCycleEnd: String?
    let individualUsage: Individual?
    struct Individual: Decodable { let plan: Plan? }
    struct Plan: Decodable {
        let enabled: Bool?
        let totalPercentUsed: Double?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
}
