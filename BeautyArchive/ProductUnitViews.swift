import SwiftData
import SwiftUI

struct ProductUnitDetail: View {
    let unit: ProductUnit
    let product: BeautyProduct
    @Query private var allUnits: [ProductUnit]
    @State private var showingEdit = false

    private var replacementEstimate: ReplacementEstimate? {
        ReplacementEstimate.calculate(for: unit, among: allUnits)
    }

    var body: some View {
        List {
            Section("使用状況") {
                LabeledContent("状態", value: unit.status.title)
                if let purchasedAt = unit.purchasedAt {
                    LabeledContent("購入日", value: purchasedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let openedAt = unit.openedAt {
                    LabeledContent("開封日", value: openedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if let finishedAt = unit.finishedAt {
                    LabeledContent("使い切り日", value: finishedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if unit.priceYen != nil || !unit.purchasedFrom.isEmpty {
                Section("購入情報") {
                    if let priceYen = unit.priceYen {
                        LabeledContent("価格", value: priceYen.formatted(.currency(code: "JPY")))
                    }
                    if !unit.purchasedFrom.isEmpty {
                        LabeledContent("購入元", value: unit.purchasedFrom)
                    }
                }
            }
            if let estimate = replacementEstimate {
                Section("買い替え目安") {
                    LabeledContent("日付", value: estimate.date.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("使用日数", value: "\(estimate.usageDays)日")
                    LabeledContent("根拠", value: estimate.source.title)
                }
            }
            if !unit.note.isEmpty {
                Section("メモ") { Text(unit.note) }
            }
        }
        .navigationTitle("1本の記録")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) { ProductUnitForm(product: product, unit: unit) }
    }
}

struct ProductUnitForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let product: BeautyProduct
    let unit: ProductUnit?

    @State private var status: ProductUnitStatus
    @State private var hasPurchasedAt: Bool
    @State private var purchasedAt: Date
    @State private var hasOpenedAt: Bool
    @State private var openedAt: Date
    @State private var finishedAt: Date
    @State private var priceText: String
    @State private var purchasedFrom: String
    @State private var note: String
    @State private var usesReplacementEstimate: Bool
    @State private var manualDaysText: String
    @State private var adjustedDaysText: String
    @State private var errorMessage: String?

    init(product: BeautyProduct, unit: ProductUnit? = nil) {
        self.product = product
        self.unit = unit
        _status = State(initialValue: unit?.status ?? .unopened)
        _hasPurchasedAt = State(initialValue: unit?.purchasedAt != nil)
        _purchasedAt = State(initialValue: unit?.purchasedAt ?? .now)
        _hasOpenedAt = State(initialValue: unit?.openedAt != nil)
        _openedAt = State(initialValue: unit?.openedAt ?? .now)
        _finishedAt = State(initialValue: unit?.finishedAt ?? .now)
        _priceText = State(initialValue: unit?.priceYen.map(String.init) ?? "")
        _purchasedFrom = State(initialValue: unit?.purchasedFrom ?? "")
        _note = State(initialValue: unit?.note ?? "")
        _usesReplacementEstimate = State(initialValue: unit?.usesReplacementEstimate ?? false)
        _manualDaysText = State(initialValue: unit?.manualUsageDays.map(String.init) ?? "")
        _adjustedDaysText = State(initialValue: unit?.adjustedUsageDays.map(String.init) ?? "")
    }

    private var trimmedPrice: String {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var priceYen: Int? { Int(trimmedPrice) }

    private var manualUsageDays: Int? {
        Int(manualDaysText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var adjustedUsageDays: Int? {
        let value = adjustedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Int(value)
    }

    private var hasValidUsageDays: Bool {
        !usesReplacementEstimate || (
            manualUsageDays.map { (1...3650).contains($0) } == true
                && (adjustedDaysText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || adjustedUsageDays.map { (1...3650).contains($0) } == true)
        )
    }

    private var hasValidPrice: Bool {
        trimmedPrice.isEmpty || priceYen.map { $0 >= 0 } == true
    }

    private var isValid: Bool {
        hasValidPrice
            && hasValidUsageDays
            && (status != .inUse || hasOpenedAt)
            && (status != .finished || !hasOpenedAt
                || Calendar.current.startOfDay(for: finishedAt) >= Calendar.current.startOfDay(for: openedAt))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("使用状況") {
                    Picker("状態", selection: $status) {
                        ForEach(ProductUnitStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Toggle("購入日を記録", isOn: $hasPurchasedAt)
                    if hasPurchasedAt {
                        DatePicker("購入日", selection: $purchasedAt, displayedComponents: .date)
                    }
                    if status != .unopened {
                        Toggle("開封日を記録", isOn: $hasOpenedAt)
                        if hasOpenedAt {
                            DatePicker("開封日", selection: $openedAt, displayedComponents: .date)
                        }
                    }
                    if status == .finished {
                        DatePicker("使い切り日", selection: $finishedAt, displayedComponents: .date)
                    }
                    if status == .inUse && !hasOpenedAt {
                        Text("使用中にするには開封日を記録してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if status == .finished && hasOpenedAt
                        && Calendar.current.startOfDay(for: finishedAt) < Calendar.current.startOfDay(for: openedAt) {
                        Text("使い切り日は開封日以降にしてください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("購入情報（任意）") {
                    TextField("価格（円）", text: $priceText)
                        .keyboardType(.numberPad)
                    if !hasValidPrice {
                        Text("0以上の整数を入力してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("購入元", text: $purchasedFrom)
                }
                Section("買い替え目安") {
                    Toggle("目安を表示", isOn: $usesReplacementEstimate)
                    if usesReplacementEstimate {
                        TextField("初回・履歴なしの使用日数", text: $manualDaysText)
                            .keyboardType(.numberPad)
                        TextField("調整する日数（任意）", text: $adjustedDaysText)
                            .keyboardType(.numberPad)
                        if !hasValidUsageDays {
                            Text("使用日数は1〜3650日の整数で入力してください。")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Text("使用中で開封日がある1本に表示します。過去の有効な使い切り履歴があれば、その中央値を優先します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("メモ（任意）") {
                    TextField("この1本についてのメモ", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(unit == nil ? "1本を登録" : "1本を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!isValid)
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let target = unit ?? ProductUnit(productID: product.id)
        target.statusRaw = status.rawValue
        target.purchasedAt = hasPurchasedAt ? Calendar.current.startOfDay(for: purchasedAt) : nil
        target.openedAt = status != .unopened && hasOpenedAt
            ? Calendar.current.startOfDay(for: openedAt) : nil
        target.finishedAt = status == .finished
            ? Calendar.current.startOfDay(for: finishedAt) : nil
        target.priceYen = trimmedPrice.isEmpty ? nil : priceYen
        target.purchasedFrom = purchasedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.usesReplacementEstimate = usesReplacementEstimate
        target.manualUsageDays = usesReplacementEstimate ? manualUsageDays : nil
        target.adjustedUsageDays = usesReplacementEstimate ? adjustedUsageDays : nil
        target.updatedAt = .now
        if unit == nil { modelContext.insert(target) }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
