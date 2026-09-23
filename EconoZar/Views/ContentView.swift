import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var router = AppRouter()
    @State private var marketStore = MarketStore()

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label("Início", systemImage: "house") }
                .tag(0)

            VaultListView()
                .tabItem { Label("Cofres", systemImage: "archivebox") }
                .tag(1)

            PersonalLedgerView()
                .tabItem { Label("PF", systemImage: "person.text.rectangle") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(.accentColor)
        .environment(router)
        .environment(marketStore)
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .sheet(isPresented: $router.showCheckIn) {
            FlexCheckInSheet()
                .environment(\.locale, Locale(identifier: "pt_BR"))
        }
        .onOpenURL { url in
            guard url.scheme == "econozar" else { return }
            router.selectedTab = 0
            router.showCheckIn = true
        }
        .task {
            WidgetBridge.publish(context: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(AppModel.preview)
        .environment(AppRouter())
        .environment(MarketStore())
}
