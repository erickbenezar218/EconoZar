import Foundation
import SwiftData

enum AppModel {
    static let container: ModelContainer = {
        makeContainer(inMemory: false)
    }()

    @MainActor
    static let preview: ModelContainer = {
        let container = makeContainer(inMemory: true)
        Bootstrap.seedIfNeeded(context: container.mainContext)
        return container
    }()

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(
                for: Vault.self,
                Contribution.self,
                FlexPlan.self,
                CashMovement.self,
                AppPreferences.self,
                configurations: configuration
            )
        } catch {
            fatalError("Falha ao criar o ModelContainer: \(error)")
        }
    }
}
