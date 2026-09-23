import Foundation

@MainActor
enum ProductNotificationScheduler {
    private static let identifierPrefix = "beautyarchive.product-replacement."

    static func reconcile(
        products: [BeautyProduct],
        units: [ProductUnit],
        enabled: Bool,
        leadDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> String? {
        let productsByID = Dictionary(
            products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let plans = units.compactMap { unit -> LocalNotificationPlan? in
            guard unit.wantsReplacementNotification,
                  let product = productsByID[unit.productID],
                  let estimate = ReplacementEstimate.calculate(
                    for: unit, among: units, calendar: calendar
                  ),
                  let fireDate = LocalNotificationReconciler.fireDate(
                    for: estimate.date, leadDays: leadDays, now: now, calendar: calendar
                  )
            else { return nil }
            return LocalNotificationPlan(
                identifier: identifierPrefix + unit.id.uuidString,
                fireDate: fireDate,
                title: "買い替えの目安です",
                body: "\(product.name) の買い替え時期が近づいています。",
                userInfo: [
                    "productID": product.id.uuidString,
                    "unitID": unit.id.uuidString
                ]
            )
        }.sorted { $0.fireDate < $1.fireDate }
        return await LocalNotificationReconciler.reconcile(
            prefix: identifierPrefix, plans: plans, enabled: enabled, calendar: calendar
        )
    }
}
