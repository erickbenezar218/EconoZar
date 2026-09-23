import Foundation
import SwiftData

enum ContributionKind: String, Codable, CaseIterable, Identifiable {
    case flexCheckIn
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flexCheckIn: "Aporte Flex"
        case .manual: "Aporte manual"
        }
    }
}

@Model
final class Contribution {
    var amount: Decimal
    var plannedAmount: Decimal
    var date: Date
    var note: String
    var kind: ContributionKind
    var vault: Vault?

    init(
        amount: Decimal,
        plannedAmount: Decimal,
        date: Date = .now,
        note: String = "",
        kind: ContributionKind,
        vault: Vault? = nil
    ) {
        self.amount = amount
        self.plannedAmount = plannedAmount
        self.date = date
        self.note = note
        self.kind = kind
        self.vault = vault
    }
}
