import Foundation

nonisolated enum ReminderNotificationAction: String {
    case tomorrow = "beautyarchive.reminder.tomorrow"
    case nextWeek = "beautyarchive.reminder.next-week"

    var title: String {
        switch self {
        case .tomorrow: "明日また通知"
        case .nextWeek: "1週間後に通知"
        }
    }

    func fireDate(
        now: Date,
        calendar: Calendar,
        notificationTimeMinutes: Int = ReminderPreferences.defaultNotificationTimeMinutes
    ) -> Date? {
        let days = self == .tomorrow ? 1 : 7
        guard (0..<24 * 60).contains(notificationTimeMinutes),
              let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
        else { return nil }
        return calendar.date(
            bySettingHour: notificationTimeMinutes / 60,
            minute: notificationTimeMinutes % 60,
            second: 0,
            of: day
        )
    }
}

nonisolated struct ReminderNotificationResponse: Sendable {
    let actionIdentifier: String
    let requestIdentifier: String
    let categoryIdentifier: String
    let userInfo: [String: String]
}

@MainActor
struct ReminderNotificationTarget {
    nonisolated enum Kind: String {
        case product = "beautyarchive.product-replacement"
        case salon = "beautyarchive.salon-booking"

        var identifierPrefix: String { rawValue + "." }
    }

    let kind: Kind
    let id: UUID
    let revision: String
    let reminderDate: Date
    let usesLeadTime: Bool
    let title: String
    let body: String
    let metadata: [String: String]

    var identifier: String { kind.identifierPrefix + id.uuidString }
    var userInfo: [String: String] {
        metadata.merging(["reminderRevision": revision]) { _, new in new }
    }

    func matches(_ response: ReminderNotificationResponse) -> Bool {
        response.requestIdentifier == identifier
            && response.categoryIdentifier == kind.rawValue
            && response.userInfo == userInfo
    }

    func plan(
        snoozes: ReminderNotificationSnoozeStore,
        leadDays: Int,
        now: Date,
        calendar: Calendar,
        notificationTimeMinutes: Int = ReminderPreferences.defaultNotificationTimeMinutes
    ) -> LocalNotificationPlan? {
        let fireDate: Date
        if let snooze = snoozes.record(for: identifier), snooze.revision == revision {
            // Retain an expired snooze until this target changes. Changing lead time must
            // not resurrect the original notification after the postponed one has fired.
            guard snooze.fireDate > now,
                  let adjustedSnoozeDate = calendar.date(
                    bySettingHour: notificationTimeMinutes / 60,
                    minute: notificationTimeMinutes % 60,
                    second: 0,
                    of: snooze.fireDate
                  ), adjustedSnoozeDate > now else { return nil }
            fireDate = adjustedSnoozeDate
        } else {
            guard let date = LocalNotificationReconciler.fireDate(
                for: reminderDate, leadDays: usesLeadTime ? leadDays : 0,
                notificationTimeMinutes: notificationTimeMinutes,
                now: now, calendar: calendar
            ) else { return nil }
            fireDate = date
        }
        return plan(fireDate: fireDate)
    }

    func plan(fireDate: Date) -> LocalNotificationPlan {
        LocalNotificationPlan(
            identifier: identifier, fireDate: fireDate, title: title, body: body,
            categoryIdentifier: kind.rawValue, userInfo: userInfo
        )
    }
}
