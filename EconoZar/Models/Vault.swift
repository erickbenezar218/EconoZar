import Foundation
import SwiftData

enum VaultKind: String, Codable, CaseIterable, Identifiable {
    case furniture
    case emergency
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .furniture: "Móveis planejados"
        case .emergency: "Reserva de emergência"
        case .free: "Meta livre"
        }
    }

    var defaultSymbol: String {
        switch self {
        case .furniture: "sofa.fill"
        case .emergency: "shield.lefthalf.filled"
        case .free: "sparkles"
        }
    }

    var summary: String {
        switch self {
        case .furniture:
            "Meta principal de longo prazo."
        case .emergency:
            "Cobre meses de custo fixo do negócio."
        case .free:
            "Caminho de investimento: ações, FIIs ou outro destino."
        }
    }
}

@Model
final class Vault {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: VaultKind
    var targetAmount: Decimal
    var targetDate: Date?
    var monthlyFixedCosts: Decimal
    var coverageMonths: Int
    var symbolName: String
    var notes: String
    /// Parte do Aporte Flex, em porcentagem. A soma dos cofres deve fechar 100.
    var flexPercent: Int = 0
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Contribution.vault)
    var contributions: [Contribution] = []

    init(
        name: String,
        kind: VaultKind,
        targetAmount: Decimal = 0,
        targetDate: Date? = nil,
        monthlyFixedCosts: Decimal = 0,
        coverageMonths: Int = 6,
        symbolName: String? = nil,
        notes: String = "",
        flexPercent: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.monthlyFixedCosts = monthlyFixedCosts
        self.coverageMonths = coverageMonths
        self.symbolName = symbolName ?? kind.defaultSymbol
        self.notes = notes
        self.flexPercent = flexPercent
        self.createdAt = createdAt
    }

    var currentAmount: Decimal {
        contributions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Reserva de emergência usa custos fixos × meses de cobertura.
    var effectiveTarget: Decimal {
        if kind == .emergency, monthlyFixedCosts > 0, coverageMonths > 0 {
            return monthlyFixedCosts * Decimal(coverageMonths)
        }
        return targetAmount
    }
}
