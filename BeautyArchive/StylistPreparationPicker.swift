import SwiftData
import SwiftUI

struct StylistPreparationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HairStyleReference.updatedAt, order: .reverse)
    private var references: [HairStyleReference]
    @Query private var photos: [ReferencePhoto]
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if references.isEmpty {
                    ContentUnavailableView {
                        Label("参考スタイルはまだありません", systemImage: "photo.stack")
                    } description: {
                        Text("写真とオーダーメモを保存すると、ここから美容師に見せられます。")
                    } actions: {
                        Button("参考スタイルを追加", systemImage: "plus") {
                            showingAdd = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(references) { reference in
                        NavigationLink {
                            StylistPresentationView(reference: reference)
                        } label: {
                            HStack(spacing: 12) {
                                if let photo = firstPhoto(for: reference),
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
                }
            }
            .navigationTitle("オーダーを準備")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if !references.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("参考スタイルを追加", systemImage: "plus") {
                            showingAdd = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { HairReferenceForm() }
        }
    }

    private func firstPhoto(for reference: HairStyleReference) -> ReferencePhoto? {
        photos.filter { $0.referenceID == reference.id }
            .min { $0.sortOrder < $1.sortOrder }
    }
}
