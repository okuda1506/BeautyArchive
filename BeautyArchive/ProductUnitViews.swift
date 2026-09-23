import SwiftData
import SwiftUI

struct ProductUnitDetail: View {
    let unit: ProductUnit
    let product: BeautyProduct
    @State private var showingEdit = false

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
    }

    private var trimmedPrice: String {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var priceYen: Int? { Int(trimmedPrice) }

    private var hasValidPrice: Bool {
        trimmedPrice.isEmpty || priceYen.map { $0 >= 0 } == true
    }

    private var isValid: Bool {
        hasValidPrice
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
