import Foundation
import SwiftData

@Model
final class Debt {
    var name: String
    var balance: Decimal
    var installment: Decimal
    var dueDay: Int
    var note: String

    init(
        name: String,
        balance: Decimal,
        installment: Decimal = 0,
        dueDay: Int = 10,
        note: String = ""
    ) {
        self.name = name
        self.balance = balance
        self.installment = installment
        self.dueDay = min(28, max(1, dueDay))
        self.note = note
    }
}
