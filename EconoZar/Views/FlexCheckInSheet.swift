import SwiftData
import SwiftUI

struct FlexCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MarketStore.self) private var marketStore
    @Query(sort: \Vault.createdAt) private var vaults: [Vault]
    @Query private var plans: [FlexPlan]
    @Query private var contributions: [Contribution]
    @Query private var movements: [CashMovement]
    @Query private var debts: [Debt]
    @Query private var preferencesList: [AppPreferences]

    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var shares: [UUID: Decimal] = [:]
    @State private var didLoad = false
    @State private var skipAmountChange = false
    @State private var savedPulse = 0

    private var preferences: AppPreferences? { preferencesList.first }
    private var plan: FlexPlan? { plans.first }
    private var planned: Decimal { plan?.amount(for: .now) ?? 0 }
    private var businessName: String { preferences?.businessName ?? "Conect Plus" }
    private var shareSum: Decimal { shares.values.reduce(Decimal(0)) { $0 + $1 } }
    private var splitMatchesTotal: Bool { FlexShare.cents(shareSum) == FlexShare.cents(amount) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BrazilCalendar.weekdayName(for: .now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Quanto você separa hoje?")
                            .font(.title3.weight(.semibold))
                    }

                    EconoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sugestão do plano")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(planned, format: .currency(code: "BRL"))
                                .font(.title2.weight(.semibold).monospacedDigit())
                        }
                    }

                    EconoCard {
                        AmountDial(amount: $amount, planned: planned)
                    }

                    if vaults.isEmpty {
                        Text("Crie um cofre antes de registrar o aporte.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Divisão de hoje")
                                .font(.headline)
                            ForEach(vaults) { vault in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vault.name)
                                        Text("\(vault.flexPercent)% do plano")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(Money.string(shares[vault.id] ?? 0))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                }
                            }
                            Button("Voltar à divisão do plano") {
                                shares = FlexShare.split(total: amount, vaults: vaults)
                            }
                            .font(.subheadline.weight(.semibold))
                            Text(splitMatchesTotal ? "A soma fecha o aporte." : "A soma está em \(Money.string(shareSum)). Ajuste os valores até fechar o total.")
                                .font(.footnote)
                                .foregroundStyle(splitMatchesTotal ? Color.secondary : Color.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nota")
                            .font(.headline)
                        TextField("Opcional", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Insights.todayFlexContributions(in: contributions).isEmpty ? "Aporte de hoje" : "Ajustar aporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar") { save() }
                        .disabled(vaults.isEmpty || !splitMatchesTotal)
                }
            }
            .sensoryFeedback(.success, trigger: savedPulse)
            .onAppear(perform: load)
            .onChange(of: amount) { _, newValue in
                if skipAmountChange {
                    skipAmountChange = false
                    return
                }
                guard didLoad else { return }
                shares = FlexShare.split(total: newValue, vaults: vaults)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func load() {
        guard !didLoad else { return }
        let todays = Insights.todayFlexContributions(in: contributions)
        if todays.isEmpty {
            amount = planned
            shares = FlexShare.split(total: planned, vaults: vaults)
        } else {
            skipAmountChange = true
            let total = todays.reduce(Decimal(0)) { $0 + $1.amount }
            amount = total
            var next = FlexShare.split(total: total, vaults: vaults)
            for item in todays {
                if let id = item.vault?.id {
                    next[id] = item.amount
                }
            }
            shares = next
            note = todays.first?.note ?? ""
        }
        didLoad = true
    }

    private func save() {
        let value = Money.clamped(amount)
        let resolvedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var jaHoje: [UUID: Decimal] = [:]
        for item in Insights.todayFlexContributions(in: contributions) {
            guard let id = item.vault?.id else { continue }
            jaHoje[id, default: 0] += item.amount
        }
        let saldos = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0.currentAmount) })
        for item in Insights.todayFlexContributions(in: contributions) {
            modelContext.delete(item)
        }

        if FlexShare.cents(value) == 0 {
            let holder = vaults.first { $0.kind == .furniture } ?? vaults.first
            if let holder {
                modelContext.insert(Contribution(
                    amount: 0,
                    plannedAmount: planned,
                    note: resolvedNote,
                    kind: .flexCheckIn,
                    vault: holder
                ))
            }
        } else {
            for vault in vaults {
                let part = shares[vault.id] ?? 0
                guard FlexShare.cents(part) > 0 else { continue }
                modelContext.insert(Contribution(
                    amount: part,
                    plannedAmount: planned,
                    note: resolvedNote,
                    kind: .flexCheckIn,
                    vault: vault
                ))
            }
        }

        try? modelContext.save()
        WidgetBridge.publish(context: modelContext)
        let payload = MarketPlan.payload(
            investidor: MarketSettings.investorName,
            negocio: businessName,
            linhas: vaults.map { vault in
                let novo: Decimal = FlexShare.cents(value) == 0 ? 0 : (shares[vault.id] ?? 0)
                let saldo = (saldos[vault.id] ?? 0) - (jaHoje[vault.id] ?? 0) + novo
                return PlanoLinha(
                    nome: vault.name,
                    tipo: vault.kind.rawValue,
                    percentual: vault.flexPercent,
                    hoje: novo,
                    saldo: saldo,
                    meta: vault.effectiveTarget,
                    dataAlvo: vault.targetDate
                )
            },
            registrado: true,
            notificar: true,
            conta: ContaPessoal.make(movements: movements, debts: debts),
            conselheiro: true
        )
        savedPulse += 1
        dismiss()
        Task { await marketStore.refresh(payload: payload) }
    }
}
