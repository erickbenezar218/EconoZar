import Foundation
import SwiftData

enum Bootstrap {
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppPreferences>())) ?? []
        guard existing.isEmpty else { return }

        let calendar = BrazilCalendar.calendar
        let furnitureDate = calendar.date(from: DateComponents(year: 2029, month: 12, day: 31))

        let furniture = Vault(
            name: "Móveis Planejados",
            kind: .furniture,
            targetAmount: 40_000,
            targetDate: furnitureDate,
            notes: "Meta principal até 2029. Os valores iniciais são um ponto de partida — ajuste quando quiser."
        )
        let emergency = Vault(
            name: "Reserva de Emergência",
            kind: .emergency,
            monthlyFixedCosts: 3_500,
            coverageMonths: 6,
            notes: "Pensada para cobrir meses de custo fixo se o caixa apertar."
        )
        let free = Vault(
            name: "Projetos Futuros",
            kind: .free,
            targetAmount: 15_000,
            notes: "Meta livre. Ex.: comprar um carro, equipamentos de rede ou uma viagem."
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
}
