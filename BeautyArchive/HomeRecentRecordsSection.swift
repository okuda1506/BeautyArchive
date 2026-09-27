import SwiftUI

struct HomeRecentRecordsSection: View {
    private struct RecentRecord: Identifiable {
        enum Destination {
            case visit(UUID)
            case product(UUID)
        }

        let id: String
        let category: String
        let date: Date
        let summary: String
        let imageData: Data?
        let symbol: String
        let destination: Destination
    }

    let visits: [SalonVisit]
    let treatments: [SalonTreatment]
    let photos: [SalonPhoto]
    let products: [BeautyProduct]
    let units: [ProductUnit]
    let onSelectVisit: (UUID) -> Void
    let onSelectProduct: (UUID) -> Void
    @State private var showingAllRecords = false

    private var records: [RecentRecord] {
        let salonRecords = visits.map { visit in
            let treatmentNames = treatments.filter { $0.visitID == visit.id }
                .map(\.name).joined(separator: "・")
            let photo = photos.filter { $0.visitID == visit.id }
                .min { $0.sortOrder < $1.sortOrder }
            return RecentRecord(
                id: "visit-\(visit.id)",
                category: "Hair",
                date: visit.date,
                summary: treatmentNames.isEmpty ? "美容院の記録" : treatmentNames,
                imageData: photo?.imageData,
                symbol: "scissors",
                destination: .visit(visit.id)
            )
        }
        let productRecords = products.flatMap { product -> [RecentRecord] in
            let productUnits = units.filter { $0.productID == product.id }
            if productUnits.isEmpty {
                return [RecentRecord(
                    id: "product-\(product.id)",
                    category: product.category == .cosmetics ? "Cosmetics" : "Fragrance",
                    date: product.createdAt,
                    summary: "\(product.name)を登録",
                    imageData: product.imageData,
                    symbol: product.category == .cosmetics ? "bag" : "sparkles",
                    destination: .product(product.id)
                )]
            }
            return productUnits.map { unit in
                let (date, event) = event(for: unit)
                return RecentRecord(
                    id: "unit-\(unit.id)",
                    category: product.category == .cosmetics ? "Cosmetics" : "Fragrance",
                    date: date,
                    summary: "\(product.name) · \(event)",
                    imageData: product.imageData,
                    symbol: product.category == .cosmetics ? "bag" : "sparkles",
                    destination: .product(product.id)
                )
            }
        }
        return (salonRecords + productRecords).sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date > $1.date
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近の記録")
                    .font(BOneTypography.section)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !records.isEmpty {
                    Button("すべて見る", systemImage: "chevron.right") {
                        showingAllRecords = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if records.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "square.text.square")
                        .font(.title2)
                    Text("まだ記録がありません")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.prefix(3))) { record in
                        if record.id != records.first?.id {
                            Divider().padding(.leading, 84)
                        }
                        recordRow(record)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .sheet(isPresented: $showingAllRecords) {
            NavigationStack {
                List(records) { record in
                    recordRow(record)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }
                .navigationTitle("最近の記録")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { showingAllRecords = false }
                    }
                }
            }
        }
    }

    private func recordRow(_ record: RecentRecord) -> some View {
        Button {
            showingAllRecords = false
            switch record.destination {
            case .visit(let id): onSelectVisit(id)
            case .product(let id): onSelectProduct(id)
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let imageData = record.imageData,
                       let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: record.symbol)
                            .font(.title3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.category)
                        .font(BOneTypography.eyebrow)
                    Text(record.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.category)、\(record.date.formatted(.dateTime.year().month().day()))、\(record.summary)")
        .accessibilityHint("記録の詳細を開く")
    }

    private func event(for unit: ProductUnit) -> (Date, String) {
        switch unit.status {
        case .unopened:
            (unit.purchasedAt ?? unit.createdAt, "購入")
        case .inUse:
            (unit.openedAt ?? unit.purchasedAt ?? unit.createdAt,
             unit.openedAt == nil ? "購入" : "使用開始")
        case .finished:
            (unit.finishedAt ?? unit.openedAt ?? unit.purchasedAt ?? unit.createdAt, "使い切り")
        case .stopped:
            (unit.finishedAt ?? unit.openedAt ?? unit.purchasedAt ?? unit.createdAt, "使用終了")
        }
    }
}
