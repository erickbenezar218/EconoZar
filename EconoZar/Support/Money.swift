import Foundation

enum BrazilCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        return calendar
    }

    static func weekdayName(for date: Date) -> String {
        let calendar = calendar
        let weekday = calendar.component(.weekday, from: date)
        return weekdayName(weekday)
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return capitalizingFirst(symbols[index])
    }

    static func shortWeekdayName(_ weekday: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return capitalizingFirst(symbols[index])
    }

    static func date(hour: Int, minute: Int, from reference: Date = .now) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: reference)
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? reference
    }

    private static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

enum Money {
    static let locale = Locale(identifier: "pt_BR")

    static func string(_ value: Decimal) -> String {
        value.formatted(.currency(code: "BRL").locale(locale))
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    static func clamped(_ value: Decimal) -> Decimal {
        rounded(max(0, value))
    }

    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    static func half(_ value: Decimal) -> Decimal {
        rounded(value / 2)
    }

    static func bump(_ value: Decimal, by delta: Decimal) -> Decimal {
        clamped(value + delta)
    }
}
