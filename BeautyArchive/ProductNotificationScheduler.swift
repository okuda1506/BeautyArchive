import Foundation

@MainActor
enum ProductNotificationScheduler {
    static func targets(
        products: [BeautyProduct],
        units: [ProductUnit],
        calendar: Calendar = .current
    ) -> [ReminderNotificationTarget] {
        let productsByID = Dictionary(
            products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return units.compactMap { unit -> ReminderNotificationTarget? in
            guard unit.wantsReplacementNotification,
                  let product = productsByID[unit.productID],
                  let estimate = ReplacementEstimate.calculate(
                    for: unit, among: units, calendar: calendar
                  ), let openedAt = unit.openedAt
            else { return nil }
            return ReminderNotificationTarget(
                kind: .product, id: unit.id,
                revision: "\(product.id.uuidString):\(openedAt.timeIntervalSince1970):\(estimate.date.timeIntervalSince1970)",
                reminderDate: estimate.date, usesLeadTime: true,
                title: "買い替えの目安です",
                body: "\(product.name) の買い替え時期が近づいています。",
                metadata: [
                    "productID": product.id.uuidString,
                    "unitID": unit.id.uuidString
                ]
            )
        }
    }
}
