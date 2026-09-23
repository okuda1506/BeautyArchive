enum ReminderPreferences {
    static let enabledKey = "reminders.enabled"
    static let leadChoiceKey = "reminders.leadChoice"
    static let customLeadDaysKey = "reminders.customLeadDays"

    static func effectiveLeadDays(choice: Int, customDays: Int) -> Int {
        choice == -1 ? max(0, customDays) : max(0, choice)
    }
}
