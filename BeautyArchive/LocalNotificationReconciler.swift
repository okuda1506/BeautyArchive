import Foundation
import UserNotifications

struct LocalNotificationPlan {
    let identifier: String
    let fireDate: Date
    let title: String
    let body: String
    let userInfo: [String: String]
}

@MainActor
enum LocalNotificationReconciler {
    static func fireDate(
        for dueDate: Date,
        leadDays: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let reminderDay = calendar.date(
            byAdding: .day, value: -max(0, leadDays),
            to: calendar.startOfDay(for: dueDate)
        ), let fireDate = calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: reminderDay
        ), fireDate > now else { return nil }
        return fireDate
    }

    static func reconcile(
        prefix: String,
        plans: [LocalNotificationPlan],
        enabled: Bool,
        calendar: Calendar = .current
    ) async -> String? {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return nil }
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorized = true
        default: authorized = false
        }
        let activePlans = enabled && authorized ? plans : []
        let desired = Dictionary(
            activePlans.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return nil }
        let existing = pending.filter { $0.identifier.hasPrefix(prefix) }
        let matchingIDs = Set(existing.compactMap { request -> String? in
            guard let plan = desired[request.identifier], matches(request, plan, calendar: calendar)
            else { return nil }
            return request.identifier
        })
        let staleIDs = existing.map(\.identifier).filter { !matchingIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        var firstError: String?
        for plan in activePlans where !matchingIDs.contains(plan.identifier) {
            guard !Task.isCancelled else { return nil }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = plan.userInfo
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: plan.fireDate
            )
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: plan.identifier, content: content, trigger: trigger
            )
            do { try await center.add(request) }
            catch { if firstError == nil { firstError = error.localizedDescription } }
        }
        return firstError
    }

    private static func matches(
        _ request: UNNotificationRequest,
        _ plan: LocalNotificationPlan,
        calendar: Calendar
    ) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
              !trigger.repeats,
              request.content.title == plan.title,
              request.content.body == plan.body
        else { return false }
        let expected = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: plan.fireDate
        )
        let actual = trigger.dateComponents
        return actual.year == expected.year
            && actual.month == expected.month
            && actual.day == expected.day
            && actual.hour == expected.hour
            && actual.minute == expected.minute
            && actual.timeZone == calendar.timeZone
    }
}
