import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SalonPhotoDraft: Identifiable {
    let id = UUID()
    let data: Data
}

struct SalonPhotoEditor: View {
    let existing: [SalonPhoto]
    @Binding var newPhotos: [SalonPhotoDraft]
    @Binding var removedPhotoIDs: Set<UUID>
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var loadError = false

    private let maximumPhotoCount = 12

    private var visibleExisting: [SalonPhoto] {
        existing.filter { !removedPhotoIDs.contains($0.id) }
    }

    private var remainingCount: Int {
        max(0, maximumPhotoCount - visibleExisting.count - newPhotos.count)
    }

    var body: some View {
        if !visibleExisting.isEmpty || !newPhotos.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(visibleExisting) { photo in
                        removableThumbnail(data: photo.imageData) {
                            removedPhotoIDs.insert(photo.id)
                        }
                    }
                    ForEach(newPhotos) { photo in
                        removableThumbnail(data: photo.data) {
                            newPhotos.removeAll { $0.id == photo.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        if remainingCount > 0 {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: remainingCount,
                matching: .images
            ) {
                Label("写真を追加", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(isLoading)
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
        }
        if isLoading { ProgressView("写真を読み込み中") }
        Text("最大12枚。保存時に表示用サイズへ縮小します。")
            .font(.caption)
            .foregroundStyle(.secondary)
        .alert("写真を読み込めませんでした", isPresented: $loadError) {
            Button("閉じる", role: .cancel) { }
        } message: {
            Text("一部の写真を読み込めませんでした。写真ライブラリの状態を確認して、もう一度選んでください。")
        }
    }

    private func removableThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            SalonPhotoImage(data: data)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .padding(4)
            }
            .accessibilityLabel("写真を削除")
        }
    }

    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            selectedItems = []
            isLoading = false
        }
        var failed = false
        for item in items.prefix(remainingCount) {
            do {
                guard let original = try await item.loadTransferable(type: Data.self),
                      let optimized = await Task.detached(priority: .userInitiated, operation: {
                          SalonPhotoImageProcessor.optimizedJPEG(original)
                      }).value else {
                    failed = true
                    continue
                }
                newPhotos.append(SalonPhotoDraft(data: optimized))
            } catch {
                failed = true
            }
        }
        loadError = failed
    }
}

struct SalonPhotoGallery: View {
    let photos: [SalonPhoto]
    @State private var selectedPhoto: SalonPhoto?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(photos) { photo in
                    Button {
                        selectedPhoto = photo
                    } label: {
                        SalonPhotoImage(data: photo.imageData)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("写真を拡大")
                }
            }
            .padding(.vertical, 4)
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            SalonPhotoFullscreen(photo: photo)
        }
    }
}

private struct SalonPhotoFullscreen: View {
    let photo: SalonPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: photo.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(MagnifyGesture().onChanged { value in
                        zoom = min(max(value.magnification, 1), 4)
                    })
                    .accessibilityLabel("施術写真")
            }
            Button("閉じる", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .tint(.white)
                .padding(20)
                .accessibilityLabel("写真を閉じる")
        }
    }
}

private struct SalonPhotoImage: View {
    let data: Data

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .clipped()
    }
}

private enum SalonPhotoImageProcessor {
    nonisolated static func optimizedJPEG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
