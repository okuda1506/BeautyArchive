import Foundation
import SwiftData

enum ProductCategory: String, CaseIterable, Identifiable {
    case cosmetics
    case fragrance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cosmetics: "化粧品"
        case .fragrance: "香水"
        }
    }
}

@Model
final class BeautyProduct {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var categoryRaw: String = ProductCategory.cosmetics.rawValue
    var purchaseURL: String = ""
    var note: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        category: ProductCategory,
        purchaseURL: String = "",
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.categoryRaw = category.rawValue
        self.purchaseURL = purchaseURL
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var category: ProductCategory {
        ProductCategory(rawValue: categoryRaw) ?? .cosmetics
    }
}
