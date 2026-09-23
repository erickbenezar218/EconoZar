import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(MarketStore.self) private var marketStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vault.createdAt) private var vaults: [Vault]
    @Query private var plans: [FlexPlan]
    @Query private var contributions: [Contribution]
    @Query private var preferencesList: [AppPreferences]

    private var preferences: AppPreferences? { preferencesList.first }
    private var plan: FlexPlan? { plans.first }
    private var plannedToday: Decimal { plan?.amount(for: .now) ?? 0 }
    private var registeredToday: Bool {
        !Insights.todayFlexContributions(in: contributions).isEmpty
    }
    private var todayFlexTotal: Decimal {
        Insights.todayFlexContributions(in: contributions).reduce(Decimal(0)) { $0 + $1.amount }
    }
    private var streak: Int { Insights.streak(in: contributions) }
    private var total: Decimal { Insights.totalSaved(in: vaults) }
    private var series: [PatrimonyPoint] { Insights.patrimonySeries(from: contributions) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if preferences?.didDismissIntro == false {
                        introCard
                    }
                    patrimonyCard
                    flexCard
                    marketCard
                    EconoCard {
                        PatrimonyChart(points: series)
                    }
                    vaultsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("EconoZar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.showCheckIn = true
                    } label: {
                        Image(systemName: registeredToday ? "checkmark.circle.fill" : "plus.circle.fill")
                    }
                    .accessibilityLabel("Registrar aporte de hoje")
                }
            }
            .task {
                guard MarketSettings.isConfigured else { return }
                while !Task.isCancelled {
                    await marketStore.refresh(payload: marketPayload(notificar: false))
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let business = preferences?.businessName, !business.isEmpty {
                    Text(business)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var introCard: some View {
        EconoCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aporte Flex")
                    .font(.headline)
                Text("Cada dia tem um valor sugerido. No check-in ele se divide entre os cofres: móveis, reserva e o caminho de investimento. R$ 0,00 não quebra a sequência.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Entendi") {
                    preferences?.didDismissIntro = true
                    try? modelContext.save()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var patrimonyCard: some View {
        EconoCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Patrimônio guardado")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(total, format: .currency(code: "BRL"))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(vaultCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var vaultCaption: String {
        let count = vaults.count
        let noun = count == 1 ? "cofre" : "cofres"
        return "Somando \(count) \(noun)"
    }

    private var marketCard: some View {
        EconoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Leitura de mercado")
                        .font(.headline)
                    Spacer()
                    if marketStore.isLoading {
                        ProgressView()
                    }
                }

                if !MarketSettings.isConfigured {
                    Text("Em Ajustes, informe o endereço do servidor (porta 8060) e a chave da API.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let reading = marketStore.reading {
                    if let selic = reading.selicMetaAnual {
                        Text("Selic meta \(selic.formatted(.number.precision(.fractionLength(2))))% a.a.")
                            .font(.subheadline.weight(.semibold))
                    }
                    if reading.pregaoAberto == true {
                        Label("Pregão aberto", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    ForEach(reading.cotacoes.filter { $0.preco != nil }.prefix(6)) { quote in
                        HStack {
                            Text(quote.rotulo)
                            Spacer()
                            if let preco = quote.preco {
                                Text(preco, format: .currency(code: "BRL").locale(Money.locale))
                                    .monospacedDigit()
                            }
                            if let variacao = quote.variacaoDiaPercent {
                                Text(signedPercent(variacao))
                                    .monospacedDigit()
                                    .foregroundStyle(variacao < 0 ? Color.red : Color.accentColor)
                            }
                        }
                        .font(.caption)
                    }
                    if let ticker = reading.sugestaoTicker {
                        Text(ticker.replacingOccurrences(of: ".SA", with: ""))
                            .font(.title3.weight(.semibold))
                        if let valor = reading.sugestaoValor {
                            Text(valor, format: .currency(code: "BRL").locale(Money.locale))
                                .font(.headline.monospacedDigit())
                        }
                    }
                    Text(reading.motivo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if reading.telegramEnviado {
                        Label("Enviado no Telegram", systemImage: "paperplane.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(reading.aviso)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let errorMessage = marketStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if MarketSettings.isConfigured {
                    Button {
                        Task { await marketStore.refresh(payload: marketPayload(notificar: false)) }
                    } label: {
                        Text(marketStore.reading == nil ? "Buscar leitura" : "Atualizar")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(marketStore.isLoading)
                }
            }
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(2)).locale(Money.locale))
        return value > 0 ? "+\(number)%" : "\(number)%"
    }

    private func marketPayload(notificar: Bool) -> LeituraPayload {
        MarketPlan.payload(
            investidor: MarketSettings.investorName,
            negocio: preferences?.businessName ?? "Conect Plus",
            linhas: vaults.map { vault in
                PlanoLinha(
                    nome: vault.name,
                    tipo: vault.kind.rawValue,
                    percentual: vault.flexPercent,
                    hoje: hojeDoDia[vault.id] ?? 0,
                    saldo: vault.currentAmount,
                    meta: vault.effectiveTarget,
                    dataAlvo: vault.targetDate
                )
            },
            registrado: registeredToday,
            notificar: notificar
        )
    }

    private var hojeDoDia: [UUID: Decimal] {
        let todays = Insights.todayFlexContributions(in: contributions)
        if !todays.isEmpty {
            var map: [UUID: Decimal] = [:]
            for item in todays {
                guard let id = item.vault?.id else { continue }
                map[id, default: 0] += item.amount
            }
            return map
        }
        return FlexShare.split(total: plannedToday, vaults: vaults)
    }

    private var flexCard: some View {
        EconoCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BrazilCalendar.weekdayName(for: .now))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Plano de hoje")
                            .font(.headline)
                    }
                    Spacer()
                    streakBadge
                }

                Text(plannedToday, format: .currency(code: "BRL"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))

                if registeredToday {
                    Label("Registrado hoje · \(Money.string(todayFlexTotal))", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("R$ 0 conta. O que interrompe a sequência é pular o dia.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    router.showCheckIn = true
                } label: {
                    Text(registeredToday ? "Ajustar aporte de hoje" : "Registrar aporte de hoje")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: streak > 0 ? "flame.fill" : "circle.dashed")
            Text(streak == 1 ? "1 dia" : "\(streak) dias")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .accessibilityLabel("Sequência de \(streak) dias")
    }

    private var vaultsCard: some View {
        EconoCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cofres")
                    .font(.headline)
                if vaults.isEmpty {
                    Text("Crie um cofre para receber os aportes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vaults) { vault in
                        NavigationLink {
                            VaultDetailView(vault: vault)
                        } label: {
                            VaultProgressRow(vault: vault)
                        }
                        .buttonStyle(.plain)
                        if vault.id != vaults.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(AppModel.preview)
        .environment(AppRouter())
        .environment(MarketStore())
}
