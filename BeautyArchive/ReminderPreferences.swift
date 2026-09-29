import Foundation

nonisolated enum ReminderPreferences {
    static let enabledKey = "reminders.enabled"
    static let leadChoiceKey = "reminders.leadChoice"
    static let customLeadDaysKey = "reminders.customLeadDays"
    static let notificationTimeKey = "reminders.notificationTimeMinutes"
    static let defaultNotificationTimeMinutes = 9 * 60

    static func notificationTimeMinutes(defaults: UserDefaults = .standard) -> Int {
        guard let value = defaults.object(forKey: notificationTimeKey) as? Int,
              (0..<24 * 60).contains(value) else {
            return defaultNotificationTimeMinutes
        }
        return value
    }

    static func effectiveLeadDays(choice: Int, customDays: Int) -> Int {
        choice == -1 ? max(0, customDays) : max(0, choice)
    }
}
