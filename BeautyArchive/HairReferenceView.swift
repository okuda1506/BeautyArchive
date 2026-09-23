import SwiftData
import SwiftUI

struct HairReferenceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HairStyleReference.updatedAt, order: .reverse)
    private var references: [HairStyleReference]
    @Query private var allPhotos: [ReferencePhoto]
    @State private var showingAdd = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if references.isEmpty {
                ContentUnavailableView(
                    "参考スタイルはまだありません",
                    systemImage: "photo.stack",
                    description: Text("次回やりたい髪型の写真とオーダーを保存できます。")
                )
            } else {
                List {
                    ForEach(references) { reference in
                        NavigationLink {
                            HairReferenceDetail(reference: reference)
                        } label: {
                            HStack(spacing: 12) {
                                if let photo = photos(for: reference).first,
                                   let image = UIImage(data: photo.imageData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "photo")
                                        .frame(width: 60, height: 60)
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reference.title).font(.headline)
                                    if !reference.memo.isEmpty {
                                        Text(reference.memo)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("参考スタイル")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("参考スタイルを追加", systemImage: "plus") { showingAdd = true }
                    .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showingAdd) { HairReferenceForm() }
        .alert("削除できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func photos(for reference: HairStyleReference) -> [ReferencePhoto] {
        allPhotos.filter { $0.referenceID == reference.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let reference = references[index]
            for photo in allPhotos where photo.referenceID == reference.id {
                modelContext.delete(photo)
            }
            modelContext.delete(reference)
        }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct HairReferenceDetail: View {
    let reference: HairStyleReference
    @Query private var allPhotos: [ReferencePhoto]
    @State private var showingEdit = false

    private var photos: [ReferencePhoto] {
        allPhotos.filter { $0.referenceID == reference.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            if !photos.isEmpty {
                Section("参考写真") {
                    PhotoGallery(photos: photos.map { StoredPhoto(id: $0.id, data: $0.imageData) })
                }
            }
            if !reference.memo.isEmpty {
                Section("オーダーメモ") { Text(reference.memo) }
            }
            if let url = validSourceURL(reference.sourceURL) {
                Section { Link("参考元を開く", destination: url) }
            }
        }
        .navigationTitle(reference.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            HairReferenceForm(reference: reference)
        }
    }
}

struct HairReferenceForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allPhotos: [ReferencePhoto]
    let reference: HairStyleReference?
    @State private var title: String
    @State private var memo: String
    @State private var sourceURL: String
    @State private var newPhotos: [PhotoDraft] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var errorMessage: String?

    init(reference: HairStyleReference? = nil) {
        self.reference = reference
        _title = State(initialValue: reference?.title ?? "")
        _memo = State(initialValue: reference?.memo ?? "")
        _sourceURL = State(initialValue: reference?.sourceURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("タイトル") {
                    TextField("例：次回のショートスタイル", text: $title)
                }
                Section("参考写真") {
                    PhotoEditor(
                        existing: existingPhotos.map { StoredPhoto(id: $0.id, data: $0.imageData) },
                        newPhotos: $newPhotos,
                        removedPhotoIDs: $removedPhotoIDs
                    )
                }
                Section("オーダーメモ（任意）") {
                    TextField("前髪・サイド・カラーなど", text: $memo, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("参考元（任意）") {
                    TextField("https://", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !sourceURL.isEmpty && validSourceURL(sourceURL) == nil {
                        Text("https:// または http:// から始まるURLを入力してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(reference == nil ? "参考スタイルを追加" : "参考スタイルを編集")
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

    private var existingPhotos: [ReferencePhoto] {
        guard let reference else { return [] }
        return allPhotos.filter { $0.referenceID == reference.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (sourceURL.isEmpty || validSourceURL(sourceURL) != nil)
    }

    private func save() {
        guard isValid else { return }
        let target = reference ?? HairStyleReference(title: title)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        target.sourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        target.updatedAt = .now
        if reference == nil { modelContext.insert(target) }
        for photo in existingPhotos where removedPhotoIDs.contains(photo.id) {
            modelContext.delete(photo)
        }
        let nextSortOrder = (existingPhotos.map(\.sortOrder).max() ?? -1) + 1
        for (index, photo) in newPhotos.enumerated() {
            modelContext.insert(ReferencePhoto(
                referenceID: target.id,
                sortOrder: nextSortOrder + index,
                imageData: photo.data
            ))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private func validSourceURL(_ value: String) -> URL? {
    let components = URLComponents(string: value)
    guard ["https", "http"].contains(components?.scheme?.lowercased() ?? ""),
          components?.host != nil else { return nil }
    return components?.url
}
