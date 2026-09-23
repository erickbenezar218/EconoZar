import SwiftData
import SwiftUI

struct CashLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CashMovement.date, order: .reverse) private var movements: [CashMovement]
    @State private var draft: CashDraft?

    private var grouped: [(day: Date, items: [CashMovement])] {
        let calendar = BrazilCalendar.calendar
        let groups = Dictionary(grouping: movements) { movement in
            calendar.startOfDay(for: movement.date)
        }
        return groups
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if movements.isEmpty {
                    ContentUnavailableView {
                        Label("Caixa vazio", systemImage: "arrow.left.arrow.right")
                    } description: {
                        Text("Registre mensalidades de Pix ou boleto e as saídas do dia. Isso não mexe no saldo dos cofres.")
                    } actions: {
                        Button("Entrada Pix") { draft = .pix }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                ForEach(group.items) { movement in
                                    movementRow(movement)
                                }
                                .onDelete { offsets in
                                    delete(group.items, at: offsets)
                                }
                            } header: {
                                HStack {
                                    Text(group.day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                    Spacer()
                                    Text(dayNet(group.items), format: .currency(code: "BRL"))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Caixa")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Mensalidade Pix", systemImage: "qrcode") { draft = .pix }
                        Button("Mensalidade Boleto", systemImage: "doc.text") { draft = .boleto }
                        Button("Saída rápida", systemImage: "arrow.up.right") { draft = .expense }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Novo lançamento")
                }
            }
            .sheet(item: $draft) { draft in
                CashMovementSheet(
                    isIncome: draft.isIncome,
                    suggestedTitle: draft.title,
                    suggestedMethod: draft.method
                )
            }
        }
    }

    private func dayNet(_ items: [CashMovement]) -> Decimal {
        items.reduce(Decimal(0)) { $0 + $1.signedAmount }
    }

    private func movementRow(_ movement: CashMovement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movement.method.symbol)
                .foregroundStyle(movement.isIncome ? Color.accentColor : Color.red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(movement.title)
                Text(movement.method.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signed(movement), format: .currency(code: "BRL"))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(movement.isIncome ? Color.accentColor : Color.red)
        }
    }

    private func signed(_ movement: CashMovement) -> Decimal {
        movement.signedAmount
    }

    private func delete(_ items: [CashMovement], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        try? modelContext.save()
    }
}

struct CashMovementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var isIncome: Bool
    var suggestedTitle: String
    var suggestedMethod: CashMethod

    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var method: CashMethod = .pix
    @State private var date = Date.now
    @State private var note = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section(isIncome ? "Entrada" : "Saída") {
                    TextField("Descrição", text: $title)
                    AmountField(title: "Valor", amount: $amount)
                    Picker("Forma", selection: $method) {
                        ForEach(CashMethod.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
                Section("Nota") {
                    TextField("Opcional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isIncome ? "Nova entrada" : "Nova saída")
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
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                title = suggestedTitle
                method = suggestedMethod
            }
        }
    }

    private func save() {
        let movement = CashMovement(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: Money.clamped(amount),
            isIncome: isIncome,
            method: method,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(movement)
        try? modelContext.save()
        dismiss()
    }
}
