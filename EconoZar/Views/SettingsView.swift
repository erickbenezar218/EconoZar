import SwiftData
import SwiftUI
import UserNotifications

struct FlexPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [FlexPlan]

    private var plan: FlexPlan? { plans.first }

    var body: some View {
        Form {
            Section {
                Text("O valor do dia é uma sugestão. No check-in você pode aumentar, reduzir ou registrar R$ 0,00 sem perder a sequência.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let plan {
                Section("Semana") {
                    ForEach(FlexPlan.displayWeekdays, id: \.self) { weekday in
                        HStack {
                            Text(BrazilCalendar.weekdayName(weekday))
                            Spacer()
                            TextField(
                                "Valor",
                                value: weekdayBinding(plan, weekday: weekday),
                                format: .currency(code: "BRL")
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                        }
                    }
                }
            }
        }
        .navigationTitle("Plano Flex")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
            WidgetBridge.publish(context: modelContext)
        }
    }

    private func weekdayBinding(_ plan: FlexPlan, weekday: Int) -> Binding<Decimal> {
        Binding {
            plan.amount(forWeekday: weekday)
        } set: { newValue in
            plan.setAmount(newValue, forWeekday: weekday)
        }
    }
}

private extension FlexPlan {
    func amount(forWeekday weekday: Int) -> Decimal {
        switch weekday {
        case 1: sunday
        case 2: monday
        case 3: tuesday
        case 4: wednesday
        case 5: thursday
        case 6: friday
        case 7: saturday
        default: 0
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferencesList: [AppPreferences]

    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var marketStatus = ""
    @State private var testingMarket = false
    @AppStorage(MarketSettings.urlKey) private var marketServerURL = ""
    @AppStorage(MarketSettings.keyKey) private var marketAPIKey = ""

    private var preferences: AppPreferences? { preferencesList.first }

    var body: some View {
        NavigationStack {
            Form {
                if let preferences {
                    Section("Negócio") {
                        TextField("Nome", text: Bindable(preferences).businessName)
                            .onSubmit { reschedule(preferences) }
                    }

                    Section("Aporte Flex") {
                        NavigationLink("Editar plano da semana") {
                            FlexPlanEditorView()
                        }
                    }

                    Section {
                        Toggle("Lembrete diário", isOn: Bindable(preferences).reminderEnabled)
                            .onChange(of: preferences.reminderEnabled) { _, _ in
                                reschedule(preferences)
                            }
                        DatePicker(
                            "Horário",
                            selection: reminderBinding(preferences),
                            displayedComponents: .hourAndMinute
                        )
                        .disabled(!preferences.reminderEnabled)
                    } header: {
                        Text("Notificação")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hora do Aporte Flex! Quanto o caixa da \(preferences.businessName) rendeu hoje?")
                            if authorization == .denied {
                                Text("As notificações estão desligadas nos Ajustes do iPhone.")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Section {
                        TextField("http://seu-servidor:8060", text: $marketServerURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Chave da API", text: $marketAPIKey)
                        Button(testingMarket ? "Testando…" : "Testar servidor") {
                            testMarket()
                        }
                        .disabled(testingMarket || marketServerURL.isEmpty || marketAPIKey.isEmpty)
                        if !marketStatus.isEmpty {
                            Text(marketStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Servidor de mercado")
                    } footer: {
                        Text("O iPhone envia o aporte do dia, o cofre e o que falta da meta. O servidor lê a Selic e as cotações, devolve a leitura e, no check-in, avisa no Telegram. Não compra nem vende.")
                    }

                    Section("Neste iPhone") {
                        LabeledContent("Cofres e caixa", value: "Neste aparelho")
                        Text("O fluxo de caixa e os aportes continuam gravados só aqui. A leitura de mercado é opcional e usa o servidor que você configurar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Tela de Início") {
                        Text("Adicione o widget Aporte Flex na Tela de Início. O toque abre o check-in do dia.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ajustes")
            .task {
                authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .onDisappear {
                WidgetBridge.publish(context: modelContext)
            }
        }
    }

    private func reminderBinding(_ preferences: AppPreferences) -> Binding<Date> {
        Binding {
            BrazilCalendar.date(hour: preferences.reminderHour, minute: preferences.reminderMinute)
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preferences.reminderHour = parts.hour ?? 18
            preferences.reminderMinute = parts.minute ?? 0
            reschedule(preferences)
        }
    }

    private func testMarket() {
        testingMarket = true
        marketStatus = ""
        let url = marketServerURL
        let key = marketAPIKey
        Task {
            defer { testingMarket = false }
            do {
                try await MarketAPI.health(baseURL: url)
                let reading = try await MarketAPI.market(baseURL: url, apiKey: key)
                if let selic = reading.selicMetaAnual {
                    let count = reading.cotacoes.filter { $0.preco != nil }.count
                    marketStatus = "Servidor ok. Selic \(selic.formatted(.number.precision(.fractionLength(2))))% · \(count) cotações."
                } else {
                    marketStatus = "Servidor ok, mas a Selic não veio nesta resposta."
                }
            } catch {
                marketStatus = error.localizedDescription
            }
        }
    }

    private func reschedule(_ preferences: AppPreferences) {
        Task {
            authorization = await NotificationScheduler.shared.apply(preferences: preferences)
            try? modelContext.save()
        }
    }
}
