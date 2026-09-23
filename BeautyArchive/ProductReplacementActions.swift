import Foundation

enum ProductReplacementActions {
    static func actions(products: [BeautyProduct], units: [ProductUnit]) -> [HomeAction] {
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return units.compactMap { unit -> HomeAction? in
            guard let product = productsByID[unit.productID],
                  let estimate = ReplacementEstimate.calculate(for: unit, among: units),
                  let openedAt = unit.openedAt
            else { return nil }
            let openedDate = openedAt.formatted(date: .abbreviated, time: .omitted)
            return HomeAction(
                id: unit.id,
                kind: .itemReplacement,
                title: product.name,
                date: estimate.date,
                imageData: product.imageData.isEmpty ? nil : product.imageData,
                detail: "開封 \(openedDate) · \(estimate.source.title)",
                productID: product.id,
                destinationURL: product.validPurchaseURL
            )
        }
        .sorted { $0.date < $1.date }
    }
}
