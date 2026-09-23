import Foundation
import SwiftData

@Model
final class FlexPlan {
    var name: String
    var sunday: Decimal
    var monday: Decimal
    var tuesday: Decimal
    var wednesday: Decimal
    var thursday: Decimal
    var friday: Decimal
    var saturday: Decimal
    var createdAt: Date

    init(
        name: String = "Plano Flex",
        sunday: Decimal = 10,
        monday: Decimal = 80,
        tuesday: Decimal = 50,
        wednesday: Decimal = 30,
        thursday: Decimal = 20,
        friday: Decimal = 50,
        saturday: Decimal = 10,
        createdAt: Date = .now
    ) {
        self.name = name
        self.sunday = sunday
        self.monday = monday
        self.tuesday = tuesday
        self.wednesday = wednesday
        self.thursday = thursday
        self.friday = friday
        self.saturday = saturday
        self.createdAt = createdAt
    }

    /// Calendar weekday: 1 = domingo … 7 = sábado.
    func amount(for date: Date, calendar: Calendar = BrazilCalendar.calendar) -> Decimal {
        switch calendar.component(.weekday, from: date) {
        case 1: sunday
        case 2: monday
        case 3: tuesday
        case 4: wednesday
        case 5: thursday
        case 6: friday
        case 7: saturday
        default: 0
        }
    }

    func setAmount(_ amount: Decimal, forWeekday weekday: Int) {
        let value = Money.clamped(amount)
        switch weekday {
        case 1: sunday = value
        case 2: monday = value
        case 3: tuesday = value
        case 4: wednesday = value
        case 5: thursday = value
        case 6: friday = value
        case 7: saturday = value
        default: break
        }
    }

    var weekdayAmounts: [Double] {
        var values = Array(repeating: 0.0, count: 8)
        values[1] = Money.double(sunday)
        values[2] = Money.double(monday)
        values[3] = Money.double(tuesday)
        values[4] = Money.double(wednesday)
        values[5] = Money.double(thursday)
        values[6] = Money.double(friday)
        values[7] = Money.double(saturday)
        return values
    }

    /// Segunda primeiro, no hábito da semana no Brasil.
    static let displayWeekdays = [2, 3, 4, 5, 6, 7, 1]
}
