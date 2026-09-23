import Foundation
import SwiftData

enum ProductUnitStatus: String, CaseIterable, Identifiable {
    case unopened
    case inUse
    case finished
    case stopped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unopened: "未開封"
        case .inUse: "使用中"
        case .finished: "使い切り"
        case .stopped: "使用終了"
        }
    }
}

@Model
final class ProductUnit {
    var id: UUID = UUID()
    var productID: UUID = UUID()
    var purchasedAt: Date? = nil
    var openedAt: Date? = nil
    var finishedAt: Date? = nil
    var priceYen: Int? = nil
    var purchasedFrom: String = ""
    var statusRaw: String = ProductUnitStatus.unopened.rawValue
    var note: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        productID: UUID,
        purchasedAt: Date? = nil,
        openedAt: Date? = nil,
        finishedAt: Date? = nil,
        priceYen: Int? = nil,
        purchasedFrom: String = "",
        status: ProductUnitStatus = .unopened,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.productID = productID
        self.purchasedAt = purchasedAt
        self.openedAt = openedAt
        self.finishedAt = finishedAt
        self.priceYen = priceYen
        self.purchasedFrom = purchasedFrom
        self.statusRaw = status.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ProductUnitStatus {
        ProductUnitStatus(rawValue: statusRaw) ?? .unopened
    }
}
