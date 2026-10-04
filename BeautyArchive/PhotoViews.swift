import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoDraft: Identifiable {
    let id = UUID()
    let data: Data
}

struct StoredPhoto: Identifiable {
    let id: UUID
    let data: Data
}

struct PhotoEditor: View {
    let existing: [StoredPhoto]
    @Binding var newPhotos: [PhotoDraft]
    @Binding var removedPhotoIDs: Set<UUID>
    @State private var showingPicker = false
    @State private var isLoading = false
    @State private var loadError = false

    private let maximumPhotoCount = 12

    private var visibleExisting: [StoredPhoto] {
        existing.filter { !removedPhotoIDs.contains($0.id) }
    }

    private var remainingCount: Int {
        max(0, maximumPhotoCount - visibleExisting.count - newPhotos.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !visibleExisting.isEmpty || !newPhotos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(visibleExisting) { photo in
                            removableThumbnail(data: photo.data) {
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
                Button {
                    showingPicker = true
                } label: {
                    Label("写真を追加", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(isLoading)
            }
            if isLoading { ProgressView("写真を読み込み中") }
            Text("最大12枚。保存時に表示用サイズへ縮小します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .background {
            SystemPhotoPickerPresenter(isPresented: $showingPicker, selectionLimit: remainingCount) { results in
                guard !results.isEmpty else { return }
                Task { await importPhotos(results) }
            }
        }
        .alert("写真を読み込めませんでした", isPresented: $loadError) {
            Button("閉じる", role: .cancel) { }
        } message: {
            Text("一部の写真を読み込めませんでした。写真ライブラリの状態を確認して、もう一度選んでください。")
        }
    }

    private func removableThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoImage(data: data)
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
    private func importPhotos(_ results: [PHPickerResult]) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }
        var failed = false
        for result in results.prefix(remainingCount) {
            do {
                guard let original = try await photoData(from: result.itemProvider),
                      let optimized = await Task.detached(priority: .userInitiated, operation: {
                          PhotoImageProcessor.optimizedJPEG(original)
                      }).value else {
                    failed = true
                    continue
                }
                newPhotos.append(PhotoDraft(data: optimized))
            } catch {
                failed = true
            }
        }
        loadError = failed
    }

    private func photoData(from provider: NSItemProvider) async throws -> Data? {
        guard let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
    }
}

/// Present directly from UIKit so the library is not embedded in another SwiftUI
/// hosting controller while the reference form is already inside stacked sheets.
private struct SystemPhotoPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let selectionLimit: Int
    let onFinish: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PresenterController { PresenterController() }

    func updateUIViewController(_ controller: PresenterController, context: Context) {
        controller.selectionLimit = selectionLimit
        controller.shouldPresent = isPresented
        controller.onFinish = { results in
            isPresented = false
            onFinish(results)
        }
        // Present outside SwiftUI's view-update transaction, once the anchor is attached.
        DispatchQueue.main.async { [weak controller] in controller?.presentIfNeeded() }
    }

    static func dismantleUIViewController(_ controller: PresenterController, coordinator: ()) {
        controller.shouldPresent = false
        controller.onFinish = nil
        controller.activePicker?.dismiss(animated: false)
    }

    final class PresenterController: UIViewController, PHPickerViewControllerDelegate {
        var shouldPresent = false
        var selectionLimit = 12
        var onFinish: (([PHPickerResult]) -> Void)?
        private(set) var activePicker: PHPickerViewController?
        private var finishing = false

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfNeeded()
        }

        func presentIfNeeded() {
            guard shouldPresent, activePicker == nil, !finishing,
                  viewIfLoaded?.window != nil else { return }
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = max(1, selectionLimit)
            configuration.selection = .ordered
            configuration.preferredAssetRepresentationMode = .compatible
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            picker.modalPresentationStyle = .fullScreen
            // Avoid interactive dismissal; the library's Cancel action owns dismissal.
            picker.isModalInPresentation = true
            activePicker = picker
            present(picker, animated: true)
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard picker === activePicker, !finishing else { return }
            finishing = true
            shouldPresent = false
            picker.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.activePicker = nil
                self.finishing = false
                // Change the form only after the UIKit transition has finished.
                self.onFinish?(results)
            }
        }
    }
}

struct PhotoGallery: View {
    let photos: [StoredPhoto]
    let thumbnailSize: CGFloat
    let centersSinglePhoto: Bool
    @State private var selectedPhoto: StoredPhoto?

    init(photos: [StoredPhoto], thumbnailSize: CGFloat = 120, centersSinglePhoto: Bool = false) {
        self.photos = photos
        self.thumbnailSize = thumbnailSize
        self.centersSinglePhoto = centersSinglePhoto
    }

    var body: some View {
        Group {
            if centersSinglePhoto, photos.count == 1, let photo = photos.first {
                photoButton(photo)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(photos) { photo in
                            photoButton(photo)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoFullscreen(photo: photo)
        }
    }

    private func photoButton(_ photo: StoredPhoto) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            PhotoImage(data: photo.data)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("写真を拡大")
    }
}

private struct PhotoFullscreen: View {
    let photo: StoredPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(MagnifyGesture().onChanged { value in
                        zoom = min(max(value.magnification, 1), 4)
                    })
                    .accessibilityLabel("写真")
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

private struct PhotoImage: View {
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

enum PhotoImageProcessor {
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
