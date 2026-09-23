import SwiftData
import SwiftUI

struct VaultListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vault.createdAt) private var vaults: [Vault]
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if vaults.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhum cofre", systemImage: "archivebox")
                    } description: {
                        Text("Crie um destino para os aportes: móveis, reserva ou uma meta livre.")
                    } actions: {
                        Button("Novo cofre") { showEditor = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(vaults) { vault in
                            NavigationLink {
                                VaultDetailView(vault: vault)
                            } label: {
                                VaultProgressRow(vault: vault)
                                    .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Cofres")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Novo cofre")
                }
            }
            .sheet(isPresented: $showEditor) {
                VaultEditorView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vaults[index])
        }
        try? modelContext.save()
        WidgetBridge.publish(context: modelContext)
    }
}

struct VaultDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var vault: Vault

    @State private var showEditor = false
    @State private var showContribution = false
    @State private var showDeleteConfirm = false

    private var projection: GoalProjection { Insights.projection(for: vault) }

    private var history: [(month: Date, items: [Contribution])] {
        let calendar = BrazilCalendar.calendar
        let groups = Dictionary(grouping: vault.contributions) { contribution in
            calendar.date(from: calendar.dateComponents([.year, .month], from: contribution.date)) ?? contribution.date
        }
        return groups
            .map { (month: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: vault.symbolName)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        Text(vault.kind.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(vault.currentAmount, format: .currency(code: "BRL"))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    ProgressView(value: projection.progress)
                        .tint(Color.accentColor)
                    Text(progressCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Meta") {
                LabeledContent("Valor atual", value: Money.string(vault.currentAmount))
                LabeledContent("Meta final", value: Money.string(vault.effectiveTarget))
                if vault.kind == .emergency {
                    LabeledContent("Cobertura", value: "\(vault.coverageMonths) meses")
                    LabeledContent("Custo fixo", value: "\(Money.string(vault.monthlyFixedCosts))/mês")
                }
                if let targetDate = vault.targetDate {
                    LabeledContent("Data alvo") {
                        Text(targetDate, format: .dateTime.day().month(.abbreviated).year())
                    }
                } else {
                    LabeledContent("Data alvo", value: "Em aberto")
                }
                LabeledContent("Previsão", value: estimateText)
            }

            if !vault.notes.isEmpty {
                Section("Notas") {
                    Text(vault.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Histórico de aportes") {
                if history.isEmpty {
                    Text("Nenhum aporte neste cofre ainda.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history, id: \.month) { group in
                        Text(group.month, format: .dateTime.month(.wide).year())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                        ForEach(group.items) { item in
                            contributionRow(item)
                        }
                    }
                }
            }
        }
        .navigationTitle(vault.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Novo aporte", systemImage: "plus") { showContribution = true }
                    Button("Editar cofre", systemImage: "pencil") { showEditor = true }
                    Button("Apagar cofre", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            VaultEditorView(vault: vault)
        }
        .sheet(isPresented: $showContribution) {
            ManualContributionSheet(vault: vault)
        }
        .confirmationDialog("Apagar este cofre e o histórico de aportes?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Apagar cofre", role: .destructive) {
                modelContext.delete(vault)
                try? modelContext.save()
                WidgetBridge.publish(context: modelContext)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var progressCaption: String {
        guard vault.effectiveTarget > 0 else { return "Defina uma meta final para acompanhar o percentual." }
        let percent = Int((projection.progress * 100).rounded())
        if projection.reached { return "Meta alcançada." }
        return "\(percent)% · faltam \(Money.string(projection.remaining))"
    }

    private var estimateText: String {
        if projection.reached { return "Concluída" }
        guard let date = projection.estimatedDate else { return "Sem ritmo ainda" }
        return date.formatted(.dateTime.month(.abbreviated).year())
    }

    private func contributionRow(_ item: Contribution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title)
                    .font(.body)
                Text(item.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.amount, format: .currency(code: "BRL"))
                .font(.body.weight(.semibold).monospacedDigit())
        }
        .swipeActions {
            Button("Apagar", role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
                WidgetBridge.publish(context: modelContext)
            }
        }
    }
}

struct ManualContributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var vault: Vault

    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section("Valor") {
                    AmountDial(amount: $amount, planned: nil)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                Section("Quando") {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
                Section("Nota") {
                    TextField("Opcional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Novo aporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                }
            }
        }
    }

    private func save() {
        let contribution = Contribution(
            amount: Money.clamped(amount),
            plannedAmount: 0,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .manual,
            vault: vault
        )
        modelContext.insert(contribution)
        try? modelContext.save()
        WidgetBridge.publish(context: modelContext)
        dismiss()
    }
}
