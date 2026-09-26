import Foundation
import SwiftData

enum PurchasePlanStatus: String {
    case planned
    case purchased
    case cancelled

    var title: String {
        switch self {
        case .planned: "購入予定"
        case .purchased: "購入済み"
        case .cancelled: "取り消し"
        }
    }
}

@Model
final class ProductPurchasePlan {
    var id: UUID = UUID()
    var productID: UUID? = nil
    var productName: String = ""
    var categoryRaw: String = ProductCategory.cosmetics.rawValue
    var plannedAt: Date = Date.now
    var hasTime: Bool = false
    var vendor: String = ""
    var purchaseURL: String = ""
    var note: String = ""
    var statusRaw: String = PurchasePlanStatus.planned.rawValue
    var purchasedAt: Date? = nil
    var completedUnitID: UUID? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        productID: UUID? = nil,
        productName: String,
        category: ProductCategory,
        plannedAt: Date,
        hasTime: Bool = false,
        vendor: String = "",
        purchaseURL: String = "",
        note: String = ""
    ) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.categoryRaw = category.rawValue
        self.plannedAt = plannedAt
        self.hasTime = hasTime
        self.vendor = vendor
        self.purchaseURL = purchaseURL
        self.note = note
    }

    var category: ProductCategory {
        ProductCategory(rawValue: categoryRaw) ?? .cosmetics
    }

    var status: PurchasePlanStatus {
        PurchasePlanStatus(rawValue: statusRaw) ?? .planned
    }

    var validPurchaseURL: URL? {
        guard let components = URLComponents(string: purchaseURL),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        return components.url
    }
}
