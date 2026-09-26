import SwiftData
import SwiftUI

struct PurchasePlanForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BeautyProduct.name) private var products: [BeautyProduct]

    let plan: ProductPurchasePlan?
    let onSave: (Date) -> Void
    @State private var category: ProductCategory
    @State private var selectedProductID: UUID?
    @State private var productName: String
    @State private var plannedAt: Date
    @State private var hasTime: Bool
    @State private var vendor: String
    @State private var purchaseURL: String
    @State private var note: String
    @State private var errorMessage: String?

    init(
        plan: ProductPurchasePlan? = nil,
        suggestedDate: Date = .now,
        onSave: @escaping (Date) -> Void = { _ in }
    ) {
        self.plan = plan
        self.onSave = onSave
        _category = State(initialValue: plan?.category ?? .cosmetics)
        _selectedProductID = State(initialValue: plan?.productID)
        _productName = State(initialValue: plan?.productName ?? "")
        let day = Calendar.current.startOfDay(for: suggestedDate)
        _plannedAt = State(initialValue: plan?.plannedAt ?? day.addingTimeInterval(10 * 3600))
        _hasTime = State(initialValue: plan?.hasTime ?? false)
        _vendor = State(initialValue: plan?.vendor ?? "")
        _purchaseURL = State(initialValue: plan?.purchaseURL ?? "")
        _note = State(initialValue: plan?.note ?? "")
    }

    private var categoryProducts: [BeautyProduct] {
        products.filter { $0.category == category }
    }

    private var selectedProduct: BeautyProduct? {
        categoryProducts.first { $0.id == selectedProductID }
    }

    private var resolvedName: String {
        (selectedProduct?.name ?? productName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        purchaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidURL: Bool {
        guard !trimmedURL.isEmpty else { return true }
        guard let components = URLComponents(string: trimmedURL) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil && components.password == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("購入するもの") {
                    Picker("カテゴリ", selection: $category) {
                        ForEach(ProductCategory.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    if !categoryProducts.isEmpty {
                        Picker("登録済みの商品", selection: $selectedProductID) {
                            Text("新しい商品").tag(nil as UUID?)
                            ForEach(categoryProducts) { product in
                                Text(product.name).tag(product.id as UUID?)
                            }
                        }
                    }
                    if selectedProduct == nil {
                        TextField("商品名", text: $productName)
                    }
                }
                Section("購入予定日") {
                    Toggle("時刻を指定", isOn: $hasTime)
                    DatePicker(
                        hasTime ? "日時" : "日付",
                        selection: $plannedAt,
                        displayedComponents: hasTime ? [.date, .hourAndMinute] : .date
                    )
                    Text("買い替え目安とは別に、購入する予定を登録します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("購入先（任意）") {
                    TextField("店舗・サイト", text: $vendor)
                    TextField("https://", text: $purchaseURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !isValidURL {
                        Text("HTTPSのURLを入力してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("メモ（任意）") {
                    TextField("購入予定についてのメモ", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(plan == nil ? "購入予定を追加" : "購入予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: category) { _, newCategory in
                if let product = products.first(where: { $0.id == selectedProductID }),
                   product.category != newCategory {
                    selectedProductID = nil
                    productName = ""
                    if purchaseURL == product.purchaseURL { purchaseURL = "" }
                }
            }
            .onChange(of: selectedProductID) { _, newID in
                if let product = categoryProducts.first(where: { $0.id == newID }) {
                    productName = product.name
                    if purchaseURL.isEmpty { purchaseURL = product.purchaseURL }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(resolvedName.isEmpty || !isValidURL)
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
        guard !resolvedName.isEmpty, isValidURL, plan?.status != .purchased else { return }
        let target = plan ?? ProductPurchasePlan(
            productName: resolvedName,
            category: category,
            plannedAt: plannedAt
        )
        target.productID = selectedProduct?.id
        target.productName = resolvedName
        target.categoryRaw = category.rawValue
        target.plannedAt = hasTime ? plannedAt : Calendar.current.startOfDay(for: plannedAt)
        target.hasTime = hasTime
        target.vendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        target.purchaseURL = trimmedURL
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.updatedAt = .now
        if plan == nil { modelContext.insert(target) }
        do {
            try modelContext.save()
            onSave(target.plannedAt)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct PurchasePlanDetail: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [BeautyProduct]
    @Query private var units: [ProductUnit]

    let plan: ProductPurchasePlan
    let onSave: (Date) -> Void
    @State private var showingEdit = false
    @State private var showingCompletion = false
    @State private var showingDelete = false
    @State private var errorMessage: String?

    private var completedUnit: ProductUnit? {
        units.first { $0.id == plan.completedUnitID }
    }

    private var completedProduct: BeautyProduct? {
        guard let completedUnit else { return nil }
        return products.first { $0.id == completedUnit.productID }
    }

    var body: some View {
        List {
            Section("購入予定") {
                LabeledContent("状態", value: plan.status.title)
                LabeledContent("カテゴリ", value: plan.category.title)
                LabeledContent("商品", value: plan.productName)
                LabeledContent(
                    "予定",
                    value: plan.hasTime
                        ? plan.plannedAt.formatted(date: .abbreviated, time: .shortened)
                        : plan.plannedAt.formatted(date: .abbreviated, time: .omitted)
                )
                if let purchasedAt = plan.purchasedAt {
                    LabeledContent("購入日", value: purchasedAt.formatted(date: .abbreviated, time: .omitted))
                }
                if !plan.vendor.isEmpty { LabeledContent("購入先", value: plan.vendor) }
                if let url = plan.validPurchaseURL {
                    Link("購入先を開く", destination: url)
                }
            }
            if !plan.note.isEmpty {
                Section("メモ") { Text(plan.note) }
            }
            if let completedUnit, let completedProduct {
                Section("購入履歴") {
                    NavigationLink("購入した1本の記録を見る") {
                        ProductUnitDetail(unit: completedUnit, product: completedProduct)
                    }
                }
            }
            Section("操作") {
                if plan.status == .planned {
                    Button("購入済みにする", systemImage: "checkmark.circle") {
                        showingCompletion = true
                    }
                    Button("予定を取り消す") { changeStatus(to: .cancelled) }
                } else if plan.status == .cancelled {
                    Button("もう一度予定に戻す") { changeStatus(to: .planned) }
                }
                Button("予定を削除", role: .destructive) { showingDelete = true }
            }
        }
        .navigationTitle(plan.productName)
        .toolbar {
            if plan.status != .purchased {
                ToolbarItem(placement: .primaryAction) {
                    Button("編集") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            PurchasePlanForm(plan: plan, onSave: onSave)
        }
        .sheet(isPresented: $showingCompletion) {
            PurchaseCompletionForm(plan: plan)
        }
        .confirmationDialog(
            "この購入予定を削除しますか？",
            isPresented: $showingDelete
        ) {
            Button("予定を削除", role: .destructive) { deletePlan() }
        } message: {
            Text("購入済みの場合も、作成された商品の購入履歴は残ります。")
        }
        .alert("操作を完了できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func changeStatus(to status: PurchasePlanStatus) {
        plan.statusRaw = status.rawValue
        plan.updatedAt = .now
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlan() {
        modelContext.delete(plan)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct PurchaseCompletionForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [BeautyProduct]
    @Query private var units: [ProductUnit]

    let plan: ProductPurchasePlan
    @State private var purchasedAt = Date.now
    @State private var vendor: String
    @State private var priceText = ""
    @State private var errorMessage: String?

    init(plan: ProductPurchasePlan) {
        self.plan = plan
        _vendor = State(initialValue: plan.vendor)
    }

    private var trimmedPrice: String {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidPrice: Bool {
        trimmedPrice.isEmpty || Int(trimmedPrice).map { $0 >= 0 } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("購入した商品") {
                    LabeledContent("商品", value: plan.productName)
                    LabeledContent("カテゴリ", value: plan.category.title)
                }
                Section("実際の購入") {
                    DatePicker("購入日", selection: $purchasedAt, displayedComponents: .date)
                    TextField("購入先（任意）", text: $vendor)
                    TextField("価格（円・任意）", text: $priceText)
                        .keyboardType(.numberPad)
                    if !isValidPrice {
                        Text("価格は0以上の整数で入力してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text("保存すると、アイテムに未開封の1本が追加されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("購入済みにする")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("記録する") { complete() }
                        .disabled(!isValidPrice || plan.status != .planned)
                }
            }
            .alert("購入を記録できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func complete() {
        guard plan.status == .planned, plan.completedUnitID == nil, isValidPrice else { return }
        let existingUnit = units.first { $0.id == plan.id }
        let productID = existingUnit?.productID ?? plan.productID
        let product = products.first { $0.id == productID }
            ?? BeautyProduct(
                id: productID ?? UUID(),
                name: plan.productName,
                category: plan.category,
                purchaseURL: plan.purchaseURL
            )
        if !products.contains(where: { $0.id == product.id }) {
            modelContext.insert(product)
        }
        let unit = existingUnit
            ?? ProductUnit(
                id: plan.id,
                productID: product.id,
                purchasedAt: Calendar.current.startOfDay(for: purchasedAt),
                priceYen: Int(trimmedPrice),
                purchasedFrom: vendor.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        if !units.contains(where: { $0.id == unit.id }) {
            modelContext.insert(unit)
        }
        plan.productID = product.id
        plan.completedUnitID = unit.id
        plan.purchasedAt = unit.purchasedAt
        plan.statusRaw = PurchasePlanStatus.purchased.rawValue
        plan.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
