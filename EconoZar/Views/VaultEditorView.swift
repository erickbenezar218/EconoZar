import SwiftData
import SwiftUI

struct VaultEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var vault: Vault?

    @State private var name = ""
    @State private var kind: VaultKind = .free
    @State private var targetAmount: Decimal = 0
    @State private var hasTargetDate = false
    @State private var targetDate = Date.now
    @State private var monthlyFixedCosts: Decimal = 0
    @State private var coverageMonths = 6
    @State private var symbolName = VaultKind.free.defaultSymbol
    @State private var notes = ""
    @State private var flexPercent = 0
    @State private var didLoad = false

    private let symbols = [
        "sofa.fill", "shield.lefthalf.filled", "sparkles", "car.fill",
        "airplane", "wifi.router", "house.fill", "gift.fill", "leaf.fill", "star.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Cofre") {
                    TextField("Nome", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(VaultKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Text(kind.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Ícone") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        symbolName == symbol ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if kind == .emergency {
                    Section("Cobertura") {
                        AmountField(title: "Custos fixos mensais", amount: $monthlyFixedCosts)
                        Stepper("\(coverageMonths) meses", value: $coverageMonths, in: 1...36)
                        LabeledContent("Meta calculada", value: Money.string(monthlyFixedCosts * Decimal(coverageMonths)))
                    }
                } else {
                    Section("Meta final") {
                        AmountField(title: "Valor", amount: $targetAmount)
                    }
                }

                Section("Parte de cada aporte") {
                    Stepper("\(flexPercent)%", value: $flexPercent, in: 0...100)
                    Text("No check-in, o valor do dia é dividido entre os cofres por esse percentual.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Data alvo") {
                    Toggle("Definir data", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Data", selection: $targetDate, displayedComponents: .date)
                    }
                }

                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(vault == nil ? "Novo cofre" : "Editar cofre")
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
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                guard vault == nil else { return }
                symbolName = newKind.defaultSymbol
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let vault else { return }
        name = vault.name
        kind = vault.kind
        targetAmount = vault.targetAmount
        monthlyFixedCosts = vault.monthlyFixedCosts
        coverageMonths = max(vault.coverageMonths, 1)
        symbolName = vault.symbolName
        notes = vault.notes
        flexPercent = vault.flexPercent
        if let date = vault.targetDate {
            hasTargetDate = true
            targetDate = date
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = hasTargetDate ? targetDate : nil
        if let vault {
            vault.name = trimmed
            vault.kind = kind
            vault.targetAmount = Money.clamped(targetAmount)
            vault.targetDate = date
            vault.monthlyFixedCosts = Money.clamped(monthlyFixedCosts)
            vault.coverageMonths = coverageMonths
            vault.symbolName = symbolName
            vault.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            vault.flexPercent = flexPercent
        } else {
            let created = Vault(
                name: trimmed,
                kind: kind,
                targetAmount: Money.clamped(targetAmount),
                targetDate: date,
                monthlyFixedCosts: Money.clamped(monthlyFixedCosts),
                coverageMonths: coverageMonths,
                symbolName: symbolName,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                flexPercent: flexPercent
            )
            modelContext.insert(created)
        }
        try? modelContext.save()
        WidgetBridge.publish(context: modelContext)
        dismiss()
    }
}

struct AmountField: View {
    var title: String
    @Binding var amount: Decimal

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $amount, format: .currency(code: "BRL"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 180)
        }
    }
}
