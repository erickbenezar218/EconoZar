import Foundation
import SwiftData

enum Bootstrap {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppPreferences>())) ?? []
        guard existing.isEmpty else { return }

        let calendar = BrazilCalendar.calendar
        let furnitureDate = calendar.date(byAdding: .year, value: 3, to: .now)

        let furniture = Vault(
            name: "Móveis Planejados",
            kind: .furniture,
            targetAmount: 40_000,
            targetDate: furnitureDate,
            notes: "Meta de 3 anos. Ajuste o valor quando tiver o orçamento dos móveis.",
            flexPercent: 60
        )
        let emergency = Vault(
            name: "Reserva de Emergência",
            kind: .emergency,
            monthlyFixedCosts: 3_500,
            coverageMonths: 6,
            notes: "Dinheiro de liquidez diária, separado dos móveis e da bolsa.",
            flexPercent: 20
        )
        let free = Vault(
            name: "Investimentos",
            kind: .free,
            targetAmount: 15_000,
            notes: "Fatia para a cesta de ações e FIIs. A compra é na corretora.",
            flexPercent: 20
        )

        let plan = FlexPlan()
        let preferences = AppPreferences(
            businessName: "Conect Plus",
            preferredVaultID: furniture.id
        )

        context.insert(furniture)
        context.insert(emergency)
        context.insert(free)
        context.insert(plan)
        context.insert(preferences)
        try? context.save()
    }

    @MainActor
    static func ensureShares(context: ModelContext) {
        let vaults = (try? context.fetch(FetchDescriptor<Vault>())) ?? []
        guard !vaults.isEmpty, vaults.allSatisfy({ $0.flexPercent == 0 }) else { return }
        FlexShare.assign(vaults.filter { $0.kind == .furniture }, total: 60)
        FlexShare.assign(vaults.filter { $0.kind == .emergency }, total: 20)
        FlexShare.assign(vaults.filter { $0.kind == .free }, total: 20)
        try? context.save()
    }
}
