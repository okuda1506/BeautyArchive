import SwiftUI

struct HomeItemsSection: View {
    let products: [BeautyProduct]
    let units: [ProductUnit]
    let onSelectProduct: (UUID) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("化粧品・香水")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !products.isEmpty {
                    Button("すべて見る", systemImage: "chevron.right", action: onShowAll)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if products.isEmpty {
                Button(action: onShowAll) {
                    HStack(spacing: 14) {
                        Image(systemName: "bag")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("アイテムはまだありません")
                                .font(.headline)
                            Text("アイテムを開いて登録する")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(ProductCategory.allCases) { category in
                    let categoryProducts = sortedProducts(in: category)
                    if !categoryProducts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(category.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(categoryProducts.count)件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(categoryProducts.prefix(2))) { product in
                                    if product.id != categoryProducts.first?.id {
                                        Divider().padding(.leading, 76)
                                    }
                                    productRow(product)
                                }
                            }
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func sortedProducts(in category: ProductCategory) -> [BeautyProduct] {
        products.filter { $0.category == category }.sorted {
            let leftActivity = max($0.updatedAt, latestUnitDate(for: $0.id))
            let rightActivity = max($1.updatedAt, latestUnitDate(for: $1.id))
            if leftActivity == rightActivity { return $0.name < $1.name }
            return leftActivity > rightActivity
        }
    }

    private func latestUnitDate(for productID: UUID) -> Date {
        units.filter { $0.productID == productID }.map(\.updatedAt).max() ?? .distantPast
    }

    private func productRow(_ product: BeautyProduct) -> some View {
        let summary = statusSummary(for: product)
        let accessibilitySummary = [product.name, product.brand, summary]
            .filter { !$0.isEmpty }.joined(separator: "、")
        return Button {
            onSelectProduct(product.id)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let image = UIImage(data: product.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: product.category == .fragrance ? "sparkles" : "bag")
                            .font(.title3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !product.brand.isEmpty {
                        Text(product.brand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("アイテムの詳細を開く")
    }

    private func statusSummary(for product: BeautyProduct) -> String {
        let productUnits = units.filter { $0.productID == product.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let unit = productUnits.first(where: { $0.status == .inUse })
            ?? productUnits.first(where: { $0.status == .unopened })
            ?? productUnits.first
        else { return "購入・使用履歴なし" }

        let date: Date?
        let dateLabel: String
        switch unit.status {
        case .inUse:
            date = unit.openedAt
            dateLabel = "開封"
        case .unopened:
            date = unit.purchasedAt
            dateLabel = "購入"
        case .finished, .stopped:
            date = unit.finishedAt ?? unit.openedAt
            dateLabel = "使用終了"
        }
        guard let date else { return unit.status.title }
        let formattedDate = date.formatted(
            .dateTime.month().day().locale(Locale(identifier: "ja_JP"))
        )
        return "\(unit.status.title) · \(dateLabel) \(formattedDate)"
    }
}
