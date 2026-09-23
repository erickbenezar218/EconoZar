import SwiftData
import SwiftUI

struct PersonalLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CashMovement.date, order: .reverse) private var movements: [CashMovement]
    @Query(sort: \Debt.name) private var debts: [Debt]

    @State private var draft: MovementDraft?
    @State private var editingDebt: Debt?

    private var conta: ContaPessoal { ContaPessoal.make(movements: movements, debts: debts) }
    private var monthItems: [CashMovement] {
        let calendar = BrazilCalendar.calendar
        return movements.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Este mês") {
                    LabeledContent("Entrou", value: Money.string(Decimal(conta.entradasMes)))
                    LabeledContent("Saiu", value: Money.string(Decimal(conta.saidasMes)))
                    LabeledContent("Sobrou", value: Money.string(Decimal(conta.entradasMes - conta.saidasMes)))
                }

                Section {
                    ForEach(monthItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.method.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.string(item.signedAmount))
                                .foregroundStyle(item.isIncome ? Color.accentColor : Color.primary)
                        }
                    }
                    .onDelete(perform: deleteMovements)
                    if monthItems.isEmpty {
                        Text("Nada lançado neste mês.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Lançamentos")
                }

                Section {
                    ForEach(debts) { debt in
                        Button {
                            editingDebt = debt
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.name)
                                        .foregroundStyle(.primary)
                                    Text("Parcela \(Money.string(debt.installment)) · dia \(debt.dueDay)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.string(debt.balance))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete(perform: deleteDebts)
                    Button("Nova dívida") { editingDebt = Debt(name: "", balance: 0) }
                } header: {
                    Text("Dívidas")
                } footer: {
                    Text("O conselheiro lê estes lançamentos. Móveis e reserva continuam no CDB. Só a fatia de investimentos pode ir para a cesta ou para cripto.")
                }
            }
            .navigationTitle("Pessoa física")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Lançar", systemImage: "plus") {
                        Button("Entrou") { draft = .income }
                        Button("Saiu") { draft = .expense }
                    }
                }
            }
            .sheet(item: $draft) { draft in
                MovementSheet(isIncome: draft.isIncome)
            }
            .sheet(item: $editingDebt) { debt in
                DebtSheet(debt: debt)
            }
        }
    }

    private func deleteMovements(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(monthItems[index])
        }
        try? modelContext.save()
    }

    private func deleteDebts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(debts[index])
        }
        try? modelContext.save()
    }
}

private struct MovementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var isIncome: Bool

    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var method: CashMethod = .pix

    var body: some View {
        NavigationStack {
            Form {
                TextField(isIncome ? "De onde veio" : "No que gastou", text: $title)
                AmountField(title: "Valor", amount: $amount)
                Picker("Forma", selection: $method) {
                    ForEach(CashMethod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            .navigationTitle(isIncome ? "Entrou" : "Saiu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount <= 0)
                }
            }
        }
    }

    private func save() {
        modelContext.insert(
            CashMovement(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: Money.clamped(amount),
                isIncome: isIncome,
                method: method
            )
        )
        try? modelContext.save()
        dismiss()
    }
}

private struct DebtSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var debt: Debt

    @State private var name = ""
    @State private var balance: Decimal = 0
    @State private var installment: Decimal = 0
    @State private var dueDay = 10
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                AmountField(title: "Saldo", amount: $balance)
                AmountField(title: "Parcela", amount: $installment)
                Stepper("Vence dia \(dueDay)", value: $dueDay, in: 1...28)
            }
            .navigationTitle(debt.name.isEmpty ? "Nova dívida" : "Dívida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                name = debt.name
                balance = debt.balance
                installment = debt.installment
                dueDay = debt.dueDay
            }
        }
    }

    private func save() {
        debt.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        debt.balance = Money.clamped(balance)
        debt.installment = Money.clamped(installment)
        debt.dueDay = dueDay
        if debt.modelContext == nil {
            modelContext.insert(debt)
        }
        try? modelContext.save()
        dismiss()
    }
}

private enum MovementDraft: String, Identifiable {
    case income
    case expense

    var id: String { rawValue }
    var isIncome: Bool { self == .income }
}
