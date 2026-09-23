import Foundation

struct WidgetSnapshot: Codable, Sendable {
    /// Índice = weekday do Calendar (1 domingo … 7 sábado). A posição 0 fica vazia.
    var weekdayAmounts: [Double]
    var totalSaved: Double
    var streak: Int
    var lastCheckIn: Date?
    var businessName: String
    var hasPlan: Bool

    static let storageKey = "econozar.widget.snapshot"
    static let appGroupID = "group.conectplusfibra.EconoZar"

    static let empty = WidgetSnapshot(
        weekdayAmounts: Array(repeating: 0, count: 8),
        totalSaved: 0,
        streak: 0,
        lastCheckIn: nil,
        businessName: "Conect Plus",
        hasPlan: false
    )

    func plannedAmount(on date: Date, calendar: Calendar = .current) -> Double {
        let weekday = calendar.component(.weekday, from: date)
        guard weekdayAmounts.indices.contains(weekday) else { return 0 }
        return weekdayAmounts[weekday]
    }

    func checkedInToday(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastCheckIn else { return false }
        return calendar.isDate(lastCheckIn, inSameDayAs: date)
    }

    /// A sequência segue viva no dia corrente mesmo antes do check-in.
    func visibleStreak(on date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let lastCheckIn, streak > 0 else { return 0 }
        if calendar.isDate(lastCheckIn, inSameDayAs: date) { return streak }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) else {
            return 0
        }
        return calendar.isDate(lastCheckIn, inSameDayAs: yesterday) ? streak : 0
    }
}
