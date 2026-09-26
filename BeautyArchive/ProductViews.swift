import PhotosUI
import SwiftData
import SwiftUI

struct ProductListView: View {
    @Binding var selectedProductID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BeautyProduct.createdAt, order: .reverse) private var products: [BeautyProduct]
    @Query private var units: [ProductUnit]
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if products.isEmpty {
                    ContentUnavailableView(
                        "商品はまだありません",
                        systemImage: "bag",
                        description: Text("化粧品や香水の商品情報を登録できます。")
                    )
                } else {
                    List {
                        ForEach(ProductCategory.allCases) { category in
                            let categoryProducts = products.filter { $0.category == category }
                            if !categoryProducts.isEmpty {
                                Section(category.title) {
                                    ForEach(categoryProducts) { product in
                                        NavigationLink(value: product.id) {
                                            HStack(spacing: 12) {
                                                if let image = UIImage(data: product.imageData) {
                                                    Image(uiImage: image)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 60, height: 60)
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        .accessibilityHidden(true)
                                                } else {
                                                    Image(systemName: "bag")
                                                        .frame(width: 60, height: 60)
                                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        .accessibilityHidden(true)
                                                }
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(product.name).font(.headline)
                                                    if !product.brand.isEmpty {
                                                        Text(product.brand)
                                                            .font(.subheadline)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                            .padding(.vertical, 3)
                                        }
                                    }
                                    .onDelete { delete($0, from: categoryProducts) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("アイテム")
            .navigationDestination(for: UUID.self) { productID in
                if let product = products.first(where: { $0.id == productID }) {
                    ProductDetail(product: product)
                } else {
                    ContentUnavailableView("商品が見つかりません", systemImage: "bag")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("商品を追加", systemImage: "plus") { showingAdd = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showingAdd) { ProductForm() }
            .alert("削除できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { openSelectedProduct() }
            .onChange(of: selectedProductID) { _, _ in openSelectedProduct() }
            .onChange(of: products.map(\.id)) { _, _ in openSelectedProduct() }
        }
    }

    private func openSelectedProduct() {
        guard let selectedProductID,
              products.contains(where: { $0.id == selectedProductID })
        else { return }
        path = [selectedProductID]
        self.selectedProductID = nil
    }

    private func delete(_ offsets: IndexSet, from categoryProducts: [BeautyProduct]) {
        for index in offsets {
            let product = categoryProducts[index]
            for unit in units where unit.productID == product.id { modelContext.delete(unit) }
            modelContext.delete(product)
        }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductDetail: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProductUnit.createdAt, order: .reverse) private var allUnits: [ProductUnit]
    let product: BeautyProduct
    @State private var showingEdit = false
    @State private var showingAddUnit = false
    @State private var errorMessage: String?

    private var units: [ProductUnit] {
        allUnits.filter { $0.productID == product.id }
    }

    var body: some View {
        List {
            if !product.imageData.isEmpty {
                Section("商品画像") {
                    PhotoGallery(
                        photos: [StoredPhoto(id: product.id, data: product.imageData)],
                        thumbnailSize: 220
                    )
                }
            }
            Section("商品") {
                LabeledContent("カテゴリ", value: product.category.title)
                if !product.brand.isEmpty {
                    LabeledContent("ブランド", value: product.brand)
                }
            }
            Section("購入・使用履歴") {
                if units.isEmpty {
                    Text("登録した1本はまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(units) { unit in
                        NavigationLink {
                            ProductUnitDetail(unit: unit, product: product)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(unit.status.title)
                                    .font(.headline)
                                if let purchasedAt = unit.purchasedAt {
                                    Text(purchasedAt, format: .dateTime.year().month().day())
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let estimate = ReplacementEstimate.calculate(for: unit, among: allUnits) {
                                    Text("買い替え目安：\(estimate.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteUnits)
                }
                Button("もう1本登録", systemImage: "plus") { showingAddUnit = true }
            }
            if let url = product.validPurchaseURL {
                Section("再購入") {
                    Link("購入先を開く", destination: url)
                }
            }
            if !product.note.isEmpty {
                Section("メモ") { Text(product.note) }
            }
        }
        .navigationTitle(product.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) { ProductForm(product: product) }
        .sheet(isPresented: $showingAddUnit) { ProductUnitForm(product: product) }
        .alert("削除できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteUnits(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(units[index]) }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductImageReview: Identifiable {
    let id = UUID()
    let image: Data
    let saveAfterReview: Bool
}

private struct ProductImageReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let saveAfterReview: Bool
    let onAccept: (Data) -> Void
    let onSaveWithoutImage: () -> Void
    @State private var imageData: Data
    @State private var selectedImage: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var isManualImage = false
    @State private var sourceImageData: Data
    @State private var isCropped = false
    @State private var showingCrop = false
    @State private var errorMessage: String?

    init(
        image: Data, saveAfterReview: Bool,
        onAccept: @escaping (Data) -> Void,
        onSaveWithoutImage: @escaping () -> Void
    ) {
        self.saveAfterReview = saveAfterReview
        self.onAccept = onAccept
        self.onSaveWithoutImage = onSaveWithoutImage
        _imageData = State(initialValue: image)
        _sourceImageData = State(initialValue: image)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text(isManualImage
                         ? "選択した画像を確認してください。"
                         : "リンク先から取得した画像です。商品写真と異なる場合は変更できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 340)
                            .accessibilityLabel("保存前の商品画像")
                    }
                    Button("トリミング", systemImage: "crop") {
                        showingCrop = true
                    }
                    .disabled(isLoadingImage)
                    if isCropped {
                        Button("元の画像に戻す", systemImage: "arrow.uturn.backward") {
                            imageData = sourceImageData
                            isCropped = false
                        }
                    }
                    PhotosPicker(selection: $selectedImage, matching: .images) {
                        Label("別の画像を選ぶ", systemImage: "photo")
                    }
                    .disabled(isLoadingImage)
                    .onChange(of: selectedImage) { _, item in
                        guard let item else { return }
                        Task { await importImage(item) }
                    }
                    if isLoadingImage { ProgressView("画像を読み込み中") }
                    if saveAfterReview {
                        Button("画像なしで保存") { onSaveWithoutImage() }
                            .disabled(isLoadingImage)
                    }
                }
                .padding()
            }
            .navigationTitle("商品画像を確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveAfterReview ? "この画像で保存" : "この画像を使用") {
                        onAccept(imageData)
                    }
                    .disabled(isLoadingImage)
                }
            }
            .sheet(isPresented: $showingCrop) {
                ProductImageCropSheet(imageData: sourceImageData) { cropped in
                    imageData = cropped
                    isCropped = true
                }
            }
            .alert("画像を読み込めませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func importImage(_ item: PhotosPickerItem) async {
        guard !isLoadingImage else { return }
        isLoadingImage = true
        defer {
            selectedImage = nil
            isLoadingImage = false
        }
        do {
            guard let original = try await item.loadTransferable(type: Data.self),
                  let optimized = await Task.detached(priority: .userInitiated, operation: {
                      PhotoImageProcessor.optimizedJPEG(original)
                  }).value else {
                errorMessage = "別の画像を選んでください。"
                return
            }
            imageData = optimized
            sourceImageData = optimized
            isCropped = false
            isManualImage = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let product: BeautyProduct?
    @State private var name: String
    @State private var brand: String
    @State private var category: ProductCategory
    @State private var purchaseURL: String
    @State private var note: String
    @State private var imageData: Data
    @State private var selectedImage: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var suppressAutomaticImageFetch = false
    @State private var imageReview: ProductImageReview?
    @State private var showingImageFetchFailure = false
    @State private var errorMessage: String?

    init(product: BeautyProduct? = nil) {
        self.product = product
        _name = State(initialValue: product?.name ?? "")
        _brand = State(initialValue: product?.brand ?? "")
        _category = State(initialValue: product?.category ?? .cosmetics)
        _purchaseURL = State(initialValue: product?.purchaseURL ?? "")
        _note = State(initialValue: product?.note ?? "")
        _imageData = State(initialValue: product?.imageData ?? Data())
    }

    private var trimmedURL: String {
        purchaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validPurchaseURL: URL? {
        guard let components = URLComponents(string: trimmedURL),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        return components.url
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (trimmedURL.isEmpty || validPurchaseURL != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名", text: $name)
                    TextField("ブランド（任意）", text: $brand)
                    Picker("カテゴリ", selection: $category) {
                        ForEach(ProductCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }
                Section("商品画像（任意）") {
                    if let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .accessibilityLabel("選択中の商品画像")
                        Button("画像を削除", role: .destructive) {
                            imageData = Data()
                            suppressAutomaticImageFetch = true
                        }
                    }
                    PhotosPicker(selection: $selectedImage, matching: .images) {
                        Label(imageData.isEmpty ? "画像を追加" : "画像を変更", systemImage: "photo")
                    }
                    .disabled(isLoadingImage)
                    .onChange(of: selectedImage) { _, item in
                        guard let item else { return }
                        Task { await importImage(item) }
                    }
                    if imageData.isEmpty, validPurchaseURL != nil {
                        Button("URLから画像を取得", systemImage: "arrow.down.circle") {
                            Task { await fetchImageFromURL(saveAfterReview: false) }
                        }
                        .disabled(isLoadingImage)
                        if product == nil && !suppressAutomaticImageFetch {
                            Text("画像なしで保存すると、購入先URLの画像を取得して確認できます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isLoadingImage { ProgressView("画像を読み込み中") }
                }
                Section("再購入先（任意）") {
                    TextField("https://", text: $purchaseURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !trimmedURL.isEmpty && validPurchaseURL == nil {
                        Text("HTTPSのURLを入力してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("メモ（任意）") {
                    TextField("商品についてのメモ", text: $note, axis: .vertical)
                }
            }
            .alert("商品画像を取得できませんでした", isPresented: $showingImageFetchFailure) {
                Button("画像なしで保存") {
                    suppressAutomaticImageFetch = true
                    persist(image: Data())
                }
                Button("入力に戻る", role: .cancel) { }
            } message: {
                Text("画像を手動で選ぶか、画像なしで商品を保存できます。")
            }
            .navigationTitle(product == nil ? "商品を追加" : "商品を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!isValid || isLoadingImage)
                }
            }
            .sheet(item: $imageReview) { review in
                ProductImageReviewSheet(
                    image: review.image,
                    saveAfterReview: review.saveAfterReview,
                    onAccept: { reviewedImage in
                        imageReview = nil
                        imageData = reviewedImage
                        suppressAutomaticImageFetch = false
                        if review.saveAfterReview { persist(image: reviewedImage) }
                    },
                    onSaveWithoutImage: {
                        imageReview = nil
                        suppressAutomaticImageFetch = true
                        persist(image: Data())
                    }
                )
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
    }

    @MainActor
    private func importImage(_ item: PhotosPickerItem) async {
        guard !isLoadingImage else { return }
        isLoadingImage = true
        defer {
            selectedImage = nil
            isLoadingImage = false
        }
        do {
            guard let original = try await item.loadTransferable(type: Data.self),
                  let optimized = await Task.detached(priority: .userInitiated, operation: {
                      PhotoImageProcessor.optimizedJPEG(original)
                  }).value else {
                errorMessage = "画像を読み込めませんでした。別の画像を選んでください。"
                return
            }
            imageData = optimized
            suppressAutomaticImageFetch = false
        } catch {
            errorMessage = "画像を読み込めませんでした。\(error.localizedDescription)"
        }
    }

    @MainActor
    private func fetchImageFromURL(saveAfterReview: Bool) async {
        guard !isLoadingImage, let url = validPurchaseURL else { return }
        isLoadingImage = true
        defer { isLoadingImage = false }
        do {
            let fetchedImage = try await ProductImageFetcher.fetch(from: url)
            guard validPurchaseURL == url else { return }
            guard let image = fetchedImage else {
                showImageFetchFailure(saveAfterReview: saveAfterReview)
                return
            }
            imageReview = ProductImageReview(image: image, saveAfterReview: saveAfterReview)
        } catch {
            guard validPurchaseURL == url else { return }
            showImageFetchFailure(saveAfterReview: saveAfterReview)
        }
    }

    private func showImageFetchFailure(saveAfterReview: Bool) {
        if saveAfterReview {
            showingImageFetchFailure = true
        } else {
            errorMessage = "画像を取得できませんでした。手動で画像を追加できます。"
        }
    }

    private func save() {
        guard isValid else { return }
        if product == nil, imageData.isEmpty, !suppressAutomaticImageFetch,
           validPurchaseURL != nil {
            Task { await fetchImageFromURL(saveAfterReview: true) }
        } else {
            persist(image: imageData)
        }
    }

    private func persist(image: Data) {
        guard isValid else { return }
        let target = product ?? BeautyProduct(name: name, category: category)
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        target.categoryRaw = category.rawValue
        target.purchaseURL = trimmedURL
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.imageData = image
        target.updatedAt = .now
        if product == nil { modelContext.insert(target) }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
