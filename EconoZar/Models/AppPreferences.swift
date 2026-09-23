import Foundation
import SwiftData

@Model
final class AppPreferences {
    var businessName: String
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var preferredVaultID: UUID?
    var didDismissIntro: Bool

    init(
        businessName: String = "Conect Plus",
        reminderEnabled: Bool = false,
        reminderHour: Int = 18,
        reminderMinute: Int = 0,
        preferredVaultID: UUID? = nil,
        didDismissIntro: Bool = false
    ) {
        self.businessName = businessName
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.preferredVaultID = preferredVaultID
        self.didDismissIntro = didDismissIntro
    }
}
