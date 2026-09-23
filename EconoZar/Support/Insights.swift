import Foundation

struct PatrimonyPoint: Identifiable {
    var id: Date { month }
    var month: Date
    var total: Double
}

struct GoalProjection {
    var remaining: Decimal
    var progress: Double
    var estimatedDate: Date?
    var reached: Bool
}

enum Insights {
    static func totalSaved(in vaults: [Vault]) -> Decimal {
        vaults.reduce(Decimal(0)) { $0 + $1.currentAmount }
    }

    static func todayFlexCheckIn(in contributions: [Contribution], now: Date = .now) -> Contribution? {
        let calendar = BrazilCalendar.calendar
        return contributions
            .filter { $0.kind == .flexCheckIn && calendar.isDate($0.date, inSameDayAs: now) }
            .max { $0.date < $1.date }
    }

    static func lastFlexCheckIn(in contributions: [Contribution]) -> Contribution? {
        contributions
            .filter { $0.kind == .flexCheckIn }
            .max { $0.date < $1.date }
    }

    /// Dias seguidos com check-in. R$ 0 conta; pular um dia zera.
    static func streak(in contributions: [Contribution], now: Date = .now) -> Int {
        let calendar = BrazilCalendar.calendar
        let days = Set(
            contributions
                .filter { $0.kind == .flexCheckIn }
                .map { calendar.startOfDay(for: $0.date) }
        )
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func projection(for vault: Vault, now: Date = .now) -> GoalProjection {
        let calendar = BrazilCalendar.calendar
        let current = vault.currentAmount
        let target = vault.effectiveTarget
        let remaining = max(Decimal(0), target - current)
        let progress: Double
        if target > 0 {
            progress = min(1, Money.double(current / target))
        } else {
            progress = 0
        }

        let reached = target > 0 && remaining == 0
        let windowStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let recentSum = vault.contributions
            .filter { $0.date >= windowStart && $0.date <= now }
            .reduce(Decimal(0)) { $0 + $1.amount }

        var estimated: Date?
        if reached {
            estimated = now
        } else if recentSum > 0 {
            let daily = recentSum / Decimal(90)
            if daily > 0 {
                let days = Money.double(remaining / daily)
                let dayCount = Int(days.rounded(.up))
                estimated = calendar.date(byAdding: .day, value: max(dayCount, 0), to: now)
            }
        }

        return GoalProjection(
            remaining: remaining,
            progress: progress,
            estimatedDate: estimated,
            reached: reached
        )
    }

    static func patrimonySeries(from contributions: [Contribution], now: Date = .now) -> [PatrimonyPoint] {
        let calendar = BrazilCalendar.calendar
        let sorted = contributions.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: first.date)) ?? first.date
        let end = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        var points: [PatrimonyPoint] = []
        var cursor = start
        var running = Decimal(0)
        var index = 0

        while cursor <= end {
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            while index < sorted.count, sorted[index].date < next {
                running += sorted[index].amount
                index += 1
            }
            points.append(PatrimonyPoint(month: cursor, total: Money.double(running)))
            cursor = next
        }
        return points
    }

    static func todayFlexContributions(in contributions: [Contribution], now: Date = .now) -> [Contribution] {
        let calendar = BrazilCalendar.calendar
        return contributions.filter { $0.kind == .flexCheckIn && calendar.isDate($0.date, inSameDayAs: now) }
    }

    static func preferredVault(in vaults: [Vault], preferences: AppPreferences?) -> Vault? {
        if let id = preferences?.preferredVaultID,
           let match = vaults.first(where: { $0.id == id }) {
            return match
        }
        return vaults.min { $0.createdAt < $1.createdAt }
    }
}

enum FlexShare {
    static func assign(_ vaults: [Vault], total: Int) {
        let ordered = vaults.sorted { $0.createdAt < $1.createdAt }
        guard !ordered.isEmpty, total > 0 else { return }
        let base = total / ordered.count
        var rest = total % ordered.count
        for vault in ordered {
            vault.flexPercent = base + (rest > 0 ? 1 : 0)
            if rest > 0 { rest -= 1 }
        }
    }

    static func split(total: Decimal, vaults: [Vault]) -> [UUID: Decimal] {
        let ordered = vaults.sorted { $0.createdAt < $1.createdAt }
        let weight = ordered.reduce(0) { $0 + max($1.flexPercent, 0) }
        guard weight > 0 else {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, Decimal(0)) })
        }
        let totalCents = cents(total)
        var rows: [(id: UUID, cents: Int)] = ordered.map { vault in
            (vault.id, totalCents * max(vault.flexPercent, 0) / weight)
        }
        let used = rows.reduce(0) { $0 + $1.cents }
        let leftover = totalCents - used
        if leftover != 0, let index = rows.indices.max(by: { rows[$0].cents < rows[$1].cents }) {
            rows[index].cents += leftover
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Decimal($0.cents) / 100) })
    }

    static func cents(_ value: Decimal) -> Int {
        var input = value * 100
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .plain)
        return NSDecimalNumber(decimal: output).intValue
    }
}
