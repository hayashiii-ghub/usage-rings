import Foundation

public enum UsageService: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex, cursor, claude
    case grokBot

    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .grokBot: return "Grok Bot"
        }
    }
}

public enum UsageState: String, Codable, Sendable {
    case ready, disabled, signInRequired, unavailable
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct ServiceUsage: Codable, Equatable, Identifiable, Sendable {
    public let service: UsageService
    public var state: UsageState
    public var windows: [UsageWindow]
    public var updatedAt: Date?

    public var id: UsageService { service }

    public init(service: UsageService, state: UsageState, windows: [UsageWindow] = [], updatedAt: Date? = nil) {
        self.service = service
        self.state = state
        self.windows = windows
        self.updatedAt = updatedAt
    }

    public var headline: UsageWindow? {
        if service == .cursor, let total = windows.first(where: { $0.id == "total" }) { return total }
        if service == .claude {
            return windows.filter { $0.id == "five_hour" || $0.id == "seven_day" }
                .min { $0.remainingPercent < $1.remainingPercent }
        }
        return windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    public func isCurrent(at date: Date) -> Bool {
        guard state == .ready, let updatedAt, date.timeIntervalSince(updatedAt) < UsageSnapshot.maximumAge,
              updatedAt <= date.addingTimeInterval(60), !windows.isEmpty else { return false }
        // A passed reset requires a new server reading, not an assumed full allowance.
        return !windows.contains { window in window.resetsAt.map { $0 <= date } ?? false }
    }

    public func remainingPercent(at date: Date) -> Double? {
        isCurrent(at: date) ? headline?.remainingPercent : nil
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let maximumAge: TimeInterval = 20 * 60
    public static let widgetKind = "UsageRings"
    public static let bridgePort: UInt16 = 52388
    public static let bridgeURL = URL(string: "http://127.0.0.1:\(bridgePort)/v1/usage")!
    public static let empty = UsageSnapshot(services: UsageService.allCases.map {
        ServiceUsage(service: $0, state: .disabled)
    })

    public var services: [ServiceUsage]

    public init(services: [ServiceUsage]) { self.services = services }

    public func usage(for service: UsageService) -> ServiceUsage {
        services.first { $0.service == service } ?? ServiceUsage(service: service, state: .disabled)
    }

    public func validityBoundaries(after date: Date) -> [Date] {
        let dates = services.flatMap { usage in
            [usage.updatedAt?.addingTimeInterval(Self.maximumAge)] + usage.windows.map(\.resetsAt)
        }.compactMap { $0 }.filter { $0 > date && $0 <= date.addingTimeInterval(Self.maximumAge) }
        return Set(dates).sorted()
    }
}
