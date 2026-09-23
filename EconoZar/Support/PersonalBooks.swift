import Foundation

struct GastoPayload: Encodable {
    var nome: String
    var valor: Double
}

struct DividaPayload: Encodable {
    var nome: String
    var saldo: Double
    var parcela: Double
    var dia: Int
}

struct ContaPessoal {
    var entradasMes: Double
    var saidasMes: Double
    var gastos: [GastoPayload]
    var dividas: [DividaPayload]

    static let vazia = ContaPessoal(entradasMes: 0, saidasMes: 0, gastos: [], dividas: [])

    static func make(movements: [CashMovement], debts: [Debt], now: Date = .now) -> ContaPessoal {
        let calendar = BrazilCalendar.calendar
        let month = movements.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        let entradas = month.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let saidas = month.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
        var grouped: [String: Decimal] = [:]
        for item in month where !item.isIncome {
            let nome = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            grouped[nome.isEmpty ? "Gasto" : nome, default: 0] += item.amount
        }
        let gastos = grouped
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { GastoPayload(nome: $0.key, valor: Money.double($0.value)) }
        let dividas = debts.map {
            DividaPayload(
                nome: $0.name,
                saldo: Money.double($0.balance),
                parcela: Money.double($0.installment),
                dia: $0.dueDay
            )
        }
        return ContaPessoal(
            entradasMes: Money.double(entradas),
            saidasMes: Money.double(saidas),
            gastos: gastos,
            dividas: dividas
        )
    }
}
