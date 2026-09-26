import SwiftUI

struct ProductImageCropSheet: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data
    let onApply: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetAtGestureStart: CGSize = .zero
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let image = UIImage(data: imageData), let cgImage = image.cgImage {
                    let side = max(120, min(geometry.size.width - 32, geometry.size.height - 220, 420))
                    let placement = ProductImageCropPlacement(
                        imageSize: CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)),
                        side: side, zoom: zoom
                    )

                    ScrollView {
                        VStack(spacing: 22) {
                            Text("正方形に切り抜きます。画像を動かして商品を中央に合わせてください。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: placement.displaySize.width,
                                       height: placement.displaySize.height)
                                .offset(placement.clamped(offset))
                                .frame(width: side, height: side)
                                .background(.black)
                                .clipped()
                                .overlay { Rectangle().stroke(Color.primary.opacity(0.8), lineWidth: 2) }
                                .contentShape(Rectangle())
                                .highPriorityGesture(dragGesture(placement: placement))
                                .simultaneousGesture(magnifyGesture(placement: placement))
                                .accessibilityLabel("トリミング範囲")

                            VStack(spacing: 8) {
                                Slider(value: Binding(
                                    get: { zoom },
                                    set: { newValue in
                                        zoom = newValue
                                        zoomAtGestureStart = newValue
                                        offset = ProductImageCropPlacement(
                                            imageSize: placement.imageSize,
                                            side: side, zoom: newValue
                                        ).clamped(offset)
                                        offsetAtGestureStart = offset
                                    }
                                ), in: 1...4)
                                .accessibilityLabel("拡大率")
                                Text("ピンチで拡大・縮小、ドラッグで位置を調整")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("トリミングを適用") {
                                guard let cropped = ProductImageCropper.crop(
                                    cgImage, placement: placement, offset: offset
                                ) else {
                                    showingError = true
                                    return
                                }
                                onApply(cropped)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                } else {
                    ContentUnavailableView("画像を読み込めませんでした", systemImage: "photo")
                }
            }
            .navigationTitle("画像をトリミング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("位置をリセット") {
                        zoom = 1
                        zoomAtGestureStart = 1
                        offset = .zero
                        offsetAtGestureStart = .zero
                    }
                }
            }
            .alert("トリミングできませんでした", isPresented: $showingError) {
                Button("閉じる", role: .cancel) { }
            } message: {
                Text("別の位置に調整して、もう一度お試しください。")
            }
        }
    }

    private func dragGesture(placement: ProductImageCropPlacement) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = placement.clamped(CGSize(
                    width: offsetAtGestureStart.width + value.translation.width,
                    height: offsetAtGestureStart.height + value.translation.height
                ))
            }
            .onEnded { _ in offsetAtGestureStart = offset }
    }

    private func magnifyGesture(placement: ProductImageCropPlacement) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(4, max(1, zoomAtGestureStart * value.magnification))
                offset = ProductImageCropPlacement(
                    imageSize: placement.imageSize, side: placement.side, zoom: zoom
                ).clamped(offset)
            }
            .onEnded { _ in
                zoomAtGestureStart = zoom
                offsetAtGestureStart = offset
            }
    }
}

struct ProductImageCropPlacement {
    let imageSize: CGSize
    let side: CGFloat
    let zoom: CGFloat

    private var scale: CGFloat {
        max(side / imageSize.width, side / imageSize.height) * zoom
    }

    var displaySize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func clamped(_ offset: CGSize) -> CGSize {
        let maxX = max(0, (displaySize.width - side) / 2)
        let maxY = max(0, (displaySize.height - side) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    func cropRect(offset: CGSize, image: CGImage) -> CGRect {
        let cropSide = min(image.width, image.height, max(1, Int((side / scale).rounded(.down))))
        let bounded = clamped(offset)
        let x = Int(((imageSize.width - CGFloat(cropSide)) / 2 - bounded.width / scale).rounded())
        let y = Int(((imageSize.height - CGFloat(cropSide)) / 2 - bounded.height / scale).rounded())
        return CGRect(
            x: min(max(0, x), image.width - cropSide),
            y: min(max(0, y), image.height - cropSide),
            width: cropSide, height: cropSide
        )
    }
}

enum ProductImageCropper {
    static func crop(
        _ image: CGImage, placement: ProductImageCropPlacement, offset: CGSize
    ) -> Data? {
        guard let cropped = image.cropping(to: placement.cropRect(offset: offset, image: image))
        else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.82)
    }
}
