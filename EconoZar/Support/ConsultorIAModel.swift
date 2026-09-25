import Foundation
import SwiftData

struct HistoricoItem: Encodable {
    var papel: String
    var texto: String
}

struct ChatPayload: Encodable {
    var mensagem: String
    var historico: [HistoricoItem]
    var investidor: String
    var negocio: String
    var caminhos: [CaminhoPayload]
    var entradasMes: Double
    var saidasMes: Double
    var gastos: [GastoPayload]
    var dividas: [DividaPayload]
}

struct ChatReply: Decodable {
    var texto: String
    var sugestao: ChatSuggestion?
}

@MainActor
@Observable
final class ConsultorIAModel {
    var draft = ""
    var isSending = false
    var errorMessage: String?

    func send(
        text: String,
        turns: [ChatTurn],
        vaults: [Vault],
        movements: [CashMovement],
        debts: [Debt],
        reading: MarketReading?,
        businessName: String,
        context: ModelContext
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pergunta = trimmed.isEmpty ? "Olhe meu plano e diga o passo de hoje." : trimmed
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        if !trimmed.isEmpty {
            context.insert(ChatTurn(role: "user", text: pergunta))
            draft = ""
            try? context.save()
        }

        let historico = turns.suffix(8).map { HistoricoItem(papel: $0.role, texto: $0.text) }
        let conta = ContaPessoal.make(movements: movements, debts: debts)
        let caminhos = vaults.map { vault in
            CaminhoPayload(
                nome: vault.name,
                tipo: vault.kind.rawValue,
                percentual: vault.flexPercent,
                hoje: 0,
                saldo: Money.double(vault.currentAmount),
                meta: Money.double(vault.effectiveTarget),
                dataAlvo: nil
            )
        }
        let payload = ChatPayload(
            mensagem: pergunta,
            historico: historico,
            investidor: MarketSettings.investorName,
            negocio: businessName,
            caminhos: caminhos,
            entradasMes: conta.entradasMes,
            saidasMes: conta.saidasMes,
            gastos: conta.gastos,
            dividas: conta.dividas
        )

        let reply: ChatReply
        if MarketSettings.isConfigured {
            do {
                reply = try await MarketAPI.chat(
                    baseURL: MarketSettings.serverURL,
                    apiKey: MarketSettings.apiKey,
                    payload: payload
                )
            } catch {
                errorMessage = error.localizedDescription
                reply = ConsultorLocal.reply(
                    nome: MarketSettings.investorName,
                    vaults: vaults,
                    reading: reading,
                    pergunta: pergunta
                )
            }
        } else {
            reply = ConsultorLocal.reply(
                nome: MarketSettings.investorName,
                vaults: vaults,
                reading: reading,
                pergunta: pergunta
            )
        }

        let turn = ChatTurn(role: "assistant", text: reply.texto)
        turn.store(reply.sugestao)
        context.insert(turn)
        try? context.save()
    }

    func approve(_ turn: ChatTurn, vaults: [Vault], context: ModelContext) {
        guard turn.decision.isEmpty, let suggestion = turn.suggestion else { return }
        guard let vault = vaults.first(where: { $0.kind == .free && $0.name == suggestion.cofre })
                ?? vaults.first(where: { $0.kind == .free }),
              vault.kind == .free else {
            errorMessage = "Só a fatia de Projetos Futuros pode registrar essa compra."
            return
        }
        let amount = Decimal(suggestion.valor)
        guard amount > 0, vault.currentAmount >= amount else {
            errorMessage = "O cofre \(vault.name) não tem saldo para esse valor."
            return
        }
        context.insert(
            Contribution(
                amount: -amount,
                plannedAmount: 0,
                note: "Compra registrada: \(suggestion.ativo). Nenhuma ordem foi enviada à corretora.",
                kind: .manual,
                vault: vault
            )
        )
        turn.decision = "approved"
        context.insert(
            ChatTurn(
                role: "assistant",
                text: "Registrei \(Money.string(amount)) de \(vault.name) como compra de \(suggestion.ativo). A ordem você faz na corretora. Reserva e móveis não foram mexidos."
            )
        )
        try? context.save()
        WidgetBridge.publish(context: context)
    }

    func decline(_ turn: ChatTurn, context: ModelContext) {
        guard turn.decision.isEmpty else { return }
        turn.decision = "declined"
        context.insert(ChatTurn(role: "assistant", text: "Beleza. O dinheiro continua no cofrinho."))
        try? context.save()
    }
}

enum ConsultorLocal {
    static func reply(nome: String, vaults: [Vault], reading: MarketReading?, pergunta: String = "") -> ChatReply {
        let livres = vaults.filter { $0.kind == .free }
        let saldo = livres.reduce(Decimal(0)) { $0 + $1.currentAmount }
        let cofre = livres.first?.name ?? "Projetos Futuros"
        let selic = reading?.selicMetaAnual
        let total = vaults.reduce(Decimal(0)) { $0 + $1.currentAmount }
        let linhas = vaults.map { vault in
            "\(vault.name): \(Money.string(vault.currentAmount)), meta \(Money.string(vault.effectiveTarget))"
        }
        let guardado = linhas.isEmpty
            ? "nenhum cofre informado"
            : linhas.joined(separator: ". ") + ". Total guardado: \(Money.string(total))"
        let candidato = reading?.cotacoes
            .filter { quote in
                guard let dy = quote.dividendYieldAnual, let selic, quote.preco != nil else { return false }
                return dy > selic
            }
            .max { ($0.dividendYieldAnual ?? 0) < ($1.dividendYieldAnual ?? 0) }
        let perguntaBaixa = pergunta.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")).lowercased()
        let querSaldo = ["quanto", "guardado", "saldo", "tenho", "reserva", "moveis", "cofre"].contains { perguntaBaixa.contains($0) }
        if querSaldo {
            return ChatReply(
                texto: "\(nome), você tem isto guardado. \(guardado).",
                sugestao: nil
            )
        }

        guard saldo > 0, let selic, let candidato, let dy = candidato.dividendYieldAnual else {
            let taxa = selic.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") + "%" } ?? "indisponível"
            return ChatReply(
                texto: "\(nome), você tem isto guardado. \(guardado). Nenhum papel da cesta mostra dividendo de 12 meses acima da Selic de \(taxa). A fatia de \(cofre) segue no cofrinho. Reserva e móveis permanecem nos cofres deles.",
                sugestao: nil
            )
        }

        let sugestao = ChatSuggestion(
            valor: Money.double(saldo),
            ativo: candidato.rotulo,
            cofre: cofre,
            rendimentoCofre: "Cofrinho em liquidez diária, perto de 100% do CDI. Selic meta \(String(format: "%.2f", selic).replacingOccurrences(of: ".", with: ","))% a.a.",
            estimativaAtivo: "\(candidato.rotulo) dividendos de 12 meses em \(String(format: "%.2f", dy).replacingOccurrences(of: ".", with: ","))%, acima da Selic."
        )
        return ChatReply(
            texto: "\(nome), você tem isto guardado. \(guardado). Na fatia de \(cofre) há \(Money.string(saldo)). \(sugestao.estimativaAtivo) Sugiro tirar \(Money.string(saldo)) só desse cofre e registrar a compra de \(candidato.rotulo). O que acha?",
            sugestao: sugestao
        )
    }
}
