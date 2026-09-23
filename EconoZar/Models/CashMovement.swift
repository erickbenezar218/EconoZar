import Foundation
import SwiftData

enum CashMethod: String, Codable, CaseIterable, Identifiable {
    case pix
    case boleto
    case cash
    case card
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pix: "Pix"
        case .boleto: "Boleto"
        case .cash: "Dinheiro"
        case .card: "Cartão"
        case .other: "Outro"
        }
    }

    var symbol: String {
        switch self {
        case .pix: "qrcode"
        case .boleto: "doc.text"
        case .cash: "banknote"
        case .card: "creditcard"
        case .other: "ellipsis.circle"
        }
    }
}

@Model
final class CashMovement {
    var title: String
    var amount: Decimal
    var isIncome: Bool
    var method: CashMethod
    var date: Date
    var note: String

    init(
        title: String,
        amount: Decimal,
        isIncome: Bool,
        method: CashMethod,
        date: Date = .now,
        note: String = ""
    ) {
        self.title = title
        self.amount = amount
        self.isIncome = isIncome
        self.method = method
        self.date = date
        self.note = note
    }

    var signedAmount: Decimal {
        isIncome ? amount : -amount
    }
}
