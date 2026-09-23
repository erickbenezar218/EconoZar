import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetBridge {
    static func publish(context: ModelContext) {
        let vaults = (try? context.fetch(FetchDescriptor<Vault>())) ?? []
        let contributions = (try? context.fetch(FetchDescriptor<Contribution>())) ?? []
        let plan = (try? context.fetch(FetchDescriptor<FlexPlan>()))?.first
        let preferences = (try? context.fetch(FetchDescriptor<AppPreferences>()))?.first
        let last = Insights.lastFlexCheckIn(in: contributions)

        let snapshot = WidgetSnapshot(
            weekdayAmounts: plan?.weekdayAmounts ?? WidgetSnapshot.empty.weekdayAmounts,
            totalSaved: Money.double(Insights.totalSaved(in: vaults)),
            streak: Insights.streak(in: contributions),
            lastCheckIn: last?.date,
            businessName: preferences?.businessName ?? "Conect Plus",
            hasPlan: plan != nil
        )

        guard
            let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }

        defaults.set(data, forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
