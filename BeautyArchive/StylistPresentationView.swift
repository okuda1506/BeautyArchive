import SwiftData
import SwiftUI

struct StylistPresentationView: View {
    let reference: HairStyleReference
    @Query(sort: \SalonVisit.date, order: .reverse) private var visits: [SalonVisit]
    @Query private var allSalonPhotos: [SalonPhoto]
    @Query private var allReferencePhotos: [ReferencePhoto]

    private var previousVisit: SalonVisit? {
        visits.first { visit in
            allSalonPhotos.contains { $0.visitID == visit.id }
        }
    }

    private var previousPhotos: [StoredPhoto] {
        guard let previousVisit else { return [] }
        return allSalonPhotos.filter { $0.visitID == previousVisit.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { StoredPhoto(id: $0.id, data: $0.imageData) }
    }

    private var referencePhotos: [StoredPhoto] {
        allReferencePhotos.filter { $0.referenceID == reference.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { StoredPhoto(id: $0.id, data: $0.imageData) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reference.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("写真をタップすると大きく表示できます")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("前回の仕上がり")
                    if let previousVisit, !previousPhotos.isEmpty {
                        Text(previousVisit.date, format: .dateTime.year().month().day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        PhotoGallery(photos: previousPhotos, thumbnailSize: 240)
                    } else {
                        emptyPhotoMessage("前回の仕上がり写真はまだありません")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("今回の参考写真")
                    if referencePhotos.isEmpty {
                        emptyPhotoMessage("参考写真はまだありません")
                    } else {
                        PhotoGallery(photos: referencePhotos, thumbnailSize: 240)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("今回のオーダー")
                    Text(reference.memo.isEmpty ? "オーダーメモはまだありません" : reference.memo)
                        .font(.body)
                        .foregroundStyle(reference.memo.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("美容師に見せる")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyPhotoMessage(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
