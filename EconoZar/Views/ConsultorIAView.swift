import SwiftData
import SwiftUI

struct ConsultorIAView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MarketStore.self) private var marketStore
    @Query(sort: \ChatTurn.createdAt) private var turns: [ChatTurn]
    @Query(sort: \Vault.createdAt) private var vaults: [Vault]
    @Query private var movements: [CashMovement]
    @Query private var debts: [Debt]
    @Query private var preferencesList: [AppPreferences]

    @State private var model = ConsultorIAModel()
    @FocusState private var composerFocused: Bool

    private var businessName: String { preferencesList.first?.businessName ?? "Conect Plus" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if turns.isEmpty && !model.isSending {
                                Text("O consultor lê a fatia de Projetos Futuros, a Selic e a cesta. Reserva e móveis ficam parados.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                            ForEach(turns) { turn in
                                bubble(turn)
                                    .id(turn.persistentModelID)
                            }
                            if model.isSending {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: turns.count) { _, _ in
                        if let last = turns.last {
                            withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                        }
                    }
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Pergunte ao consultor", text: $model.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await enviar() } }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button {
                        Task { await enviar() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(model.isSending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Consultor")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fechar") { composerFocused = false }
                }
            }
            .task {
                if marketStore.reading == nil, MarketSettings.isConfigured {
                    await marketStore.refresh(payload: nil)
                }
                guard turns.isEmpty else { return }
                await enviar(texto: "")
            }
        }
    }

    private func bubble(_ turn: ChatTurn) -> some View {
        VStack(alignment: turn.isUser ? .trailing : .leading, spacing: 8) {
            Text(turn.text)
                .font(.body)
                .foregroundStyle(turn.isUser ? Color.white : Color.primary)
                .padding(12)
                .background(
                    turn.isUser ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .frame(maxWidth: 320, alignment: turn.isUser ? .trailing : .leading)

            if let suggestion = turn.suggestion, !turn.isUser {
                suggestionCard(suggestion, turn: turn)
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.isUser ? .trailing : .leading)
    }

    private func suggestionCard(_ suggestion: ChatSuggestion, turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.ativo)
                .font(.headline)
            Text("Tirar \(suggestion.valor, format: .currency(code: "BRL")) de \(suggestion.cofre)")
                .font(.subheadline.weight(.semibold))
            Text(suggestion.rendimentoCofre)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(suggestion.estimativaAtivo)
                .font(.caption)
                .foregroundStyle(.secondary)
            if turn.decision.isEmpty {
                HStack {
                    Button("Aprovar e Registrar Compra") {
                        model.approve(turn, vaults: vaults, context: modelContext)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Agora Não") {
                        model.decline(turn, context: modelContext)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
            } else {
                Text(turn.decision == "approved" ? "Compra registrada no app." : "Você deixou para depois.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func enviar(texto: String? = nil) async {
        await model.send(
            text: texto ?? model.draft,
            turns: turns,
            vaults: vaults,
            movements: movements,
            debts: debts,
            reading: marketStore.reading,
            businessName: businessName,
            context: modelContext
        )
    }
}
