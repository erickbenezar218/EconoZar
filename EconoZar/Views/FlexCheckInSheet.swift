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
    @Query private var preferencesList: [AppPreferences]

    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var vaultID: UUID?
    @State private var didLoad = false
    @State private var savedPulse = 0

    private var preferences: AppPreferences? { preferencesList.first }
    private var plan: FlexPlan? { plans.first }
    private var planned: Decimal { plan?.amount(for: .now) ?? 0 }
    private var existing: Contribution? { Insights.todayFlexCheckIn(in: contributions) }
    private var cashToday: (income: Decimal, expense: Decimal) { Insights.cashToday(in: movements) }
    private var businessName: String { preferences?.businessName ?? "seu negócio" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BrazilCalendar.weekdayName(for: .now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Quanto o caixa da \(businessName) rendeu hoje?")
                            .font(.title3.weight(.semibold))
                    }

                    EconoCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sugestão do plano")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(planned, format: .currency(code: "BRL"))
                                .font(.title2.weight(.semibold).monospacedDigit())
                            HStack {
                                Text("Entradas \(Money.string(cashToday.income))")
                                Text("·")
                                Text("Saídas \(Money.string(cashToday.expense))")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cofre de destino")
                                .font(.headline)
                            Picker("Cofre", selection: $vaultID) {
                                ForEach(vaults) { vault in
                                    Text(vault.name).tag(Optional(vault.id))
                                }
                            }
                            .pickerStyle(.menu)
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
            .navigationTitle(existing == nil ? "Aporte de hoje" : "Ajustar aporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Registrar") { save() }
                        .disabled(vaults.isEmpty || vaultID == nil)
                }
            }
            .sensoryFeedback(.success, trigger: savedPulse)
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            amount = existing.amount
            note = existing.note
            vaultID = existing.vault?.id
        } else {
            amount = planned
            vaultID = Insights.preferredVault(in: vaults, preferences: preferences)?.id
        }
    }

    private func save() {
        guard let vaultID, let vault = vaults.first(where: { $0.id == vaultID }) else { return }
        let value = Money.clamped(amount)
        let resolvedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.amount = value
            existing.plannedAmount = planned
            existing.note = resolvedNote
            existing.date = .now
            existing.vault = vault
        } else {
            let contribution = Contribution(
                amount: value,
                plannedAmount: planned,
                note: resolvedNote,
                kind: .flexCheckIn,
                vault: vault
            )
            modelContext.insert(contribution)
        }

        preferences?.preferredVaultID = vault.id
        try? modelContext.save()
        WidgetBridge.publish(context: modelContext)
        let payload = LeituraPayload(
            aporte: Money.double(value),
            registrado: true,
            negocio: businessName,
            cofre: vault.name,
            tipoCofre: vault.kind.rawValue,
            faltaMeta: Money.double(Insights.projection(for: vault).remaining),
            notificar: true
        )
        savedPulse += 1
        dismiss()
        Task { await marketStore.refresh(payload: payload) }
    }
}
