import Foundation

struct RateLimitsResponse: Decodable, Equatable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsSummary?
}

struct RateLimitResetCreditsSummary: Decodable, Equatable {
    let availableCount: Int64
    let credits: [RateLimitResetCredit]?

    var nextExpiration: Int64? {
        credits?
            .filter { $0.status == "available" }
            .compactMap(\.expiresAt)
            .min()
    }
}

struct RateLimitResetCredit: Decodable, Equatable {
    let expiresAt: Int64?
    let status: String
    let title: String?
}

struct RateLimitSnapshot: Decodable, Equatable, Identifiable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
    let individualLimit: SpendControlLimitSnapshot?
    let planType: String?
    let rateLimitReachedType: String?

    var id: String { limitId ?? limitName ?? "default" }

    var isLunaReserve: Bool {
        [limitId, limitName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.replacingOccurrences(of: "_", with: "-") }
            .contains("gpt-reserve")
    }

    var displayName: String {
        if isLunaReserve { return "Luna Reserve" }
        if let limitName, !limitName.isEmpty {
            return limitName
        }
        if limitId == "codex" || limitId == nil {
            return "Codex"
        }
        return limitId?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Codex"
    }

    func usingLimitIdIfMissing(_ fallback: String) -> RateLimitSnapshot {
        guard limitId?.isEmpty != false else { return self }
        return RateLimitSnapshot(
            limitId: fallback,
            limitName: limitName,
            primary: primary,
            secondary: secondary,
            credits: credits,
            individualLimit: individualLimit,
            planType: planType,
            rateLimitReachedType: rateLimitReachedType
        )
    }

    var fiveHourWindow: RateLimitWindow? {
        [primary, secondary]
            .compactMap { $0 }
            .first(where: { $0.windowDurationMins == 300 })
    }

    var weeklyWindow: RateLimitWindow? {
        [primary, secondary]
            .compactMap { $0 }
            .first(where: { $0.windowDurationMins == 10_080 })
    }
}

struct RateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }
}

struct CreditsSnapshot: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct SpendControlLimitSnapshot: Decodable, Equatable {
    let limit: String
    let remainingPercent: Int
    let resetsAt: Int64
    let used: String
}

struct AccountUsageResponse: Decodable, Equatable {
    let summary: AccountTokenUsageSummary
    let dailyUsageBuckets: [AccountTokenUsageDailyBucket]?
}

struct AccountTokenUsageSummary: Decodable, Equatable {
    let currentStreakDays: Int64?
    let lifetimeTokens: Int64?
    let longestRunningTurnSec: Int64?
    let longestStreakDays: Int64?
    let peakDailyTokens: Int64?
}

struct AccountTokenUsageDailyBucket: Decodable, Equatable {
    let startDate: String
    let tokens: Int64
}

struct CodexUsageSnapshot: Equatable {
    let defaultRateLimits: RateLimitSnapshot
    let rateLimitsById: [String: RateLimitSnapshot]
    let rateLimitResetCredits: RateLimitResetCreditsSummary?
    let accountUsage: AccountUsageResponse?
    let fetchedAt: Date

    var codexRateLimits: RateLimitSnapshot {
        rateLimitsById["codex"] ?? defaultRateLimits
    }

    var additionalRateLimits: [RateLimitSnapshot] {
        rateLimitsById
            .filter { $0.key != "codex" }
            .map { $0.value.usingLimitIdIfMissing($0.key) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var todayTokens: Int64? {
        let key = UsageFormatters.isoDay.string(from: Date())
        return accountUsage?.dailyUsageBuckets?.first(where: { $0.startDate == key })?.tokens
    }
}

enum UsageFormatters {
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let compactNumber: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func resetLabel(_ timestamp: Int64?, now: Date = Date()) -> String {
        guard let timestamp else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let interval = date.timeIntervalSince(now)
        if Calendar.current.isDate(date, inSameDayAs: now) || (interval >= 0 && interval < 86_400) {
            return shortTime.string(from: date)
        }
        return shortDate.string(from: date)
    }

    static func fullResetLabel(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "—" }
        return fullDateTime.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func tokenCount(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let magnitude = Double(value)
        let divisor: Double
        let suffix: String
        switch abs(magnitude) {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return compactNumber.string(from: NSNumber(value: value)) ?? String(value)
        }
        let number = compactNumber.string(from: NSNumber(value: magnitude / divisor)) ?? "—"
        return number + suffix
    }
}
