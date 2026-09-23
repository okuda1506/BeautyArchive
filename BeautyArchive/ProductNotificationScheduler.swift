import Foundation
import UserNotifications

@MainActor
enum ProductNotificationScheduler {
    private static let identifierPrefix = "beautyarchive.product-replacement."

    private struct Plan {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        let productID: UUID
        let unitID: UUID
    }

    static func reconcile(
        products: [BeautyProduct],
        units: [ProductUnit],
        enabled: Bool,
        leadDays: Int,
        now: Date = .now,
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
        let plans = enabled && authorized
            ? plannedNotifications(
                products: products, units: units, leadDays: leadDays,
                now: now, calendar: calendar
            )
            : []
        let desired = Dictionary(plans.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return nil }
        let existing = pending.filter { $0.identifier.hasPrefix(identifierPrefix) }
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
        for plan in plans where !matchingIDs.contains(plan.identifier) {
            guard !Task.isCancelled else { return nil }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = [
                "productID": plan.productID.uuidString,
                "unitID": plan.unitID.uuidString
            ]
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

    private static func plannedNotifications(
        products: [BeautyProduct],
        units: [ProductUnit],
        leadDays: Int,
        now: Date,
        calendar: Calendar
    ) -> [Plan] {
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return units.compactMap { unit -> Plan? in
            guard unit.wantsReplacementNotification,
                  let product = productsByID[unit.productID],
                  let estimate = ReplacementEstimate.calculate(for: unit, among: units, calendar: calendar),
                  let reminderDay = calendar.date(byAdding: .day, value: -max(0, leadDays), to: estimate.date),
                  let fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDay),
                  fireDate > now
            else { return nil }
            return Plan(
                identifier: identifierPrefix + unit.id.uuidString,
                fireDate: fireDate,
                title: "買い替えの目安です",
                body: "\(product.name) の買い替え時期が近づいています。",
                productID: product.id,
                unitID: unit.id
            )
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    private static func matches(_ request: UNNotificationRequest, _ plan: Plan, calendar: Calendar) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
              !trigger.repeats,
              request.content.title == plan.title,
              request.content.body == plan.body
        else { return false }
        let expected = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
        let actual = trigger.dateComponents
        return actual.year == expected.year
            && actual.month == expected.month
            && actual.day == expected.day
            && actual.hour == expected.hour
            && actual.minute == expected.minute
            && actual.timeZone == calendar.timeZone
    }
}
