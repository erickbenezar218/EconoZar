import SwiftUI
import SwiftData

@main
struct EconoZarApp: App {
    init() {
        Bootstrap.seedIfNeeded(context: AppModel.container.mainContext)
        Bootstrap.ensureShares(context: AppModel.container.mainContext)
        NotificationScheduler.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppModel.container)
    }
}
