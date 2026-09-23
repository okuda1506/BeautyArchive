import Foundation
import SwiftData

@Model
final class HairStyleReference {
    var id: UUID = UUID()
    var title: String = ""
    var memo: String = ""
    var sourceURL: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        title: String,
        memo: String = "",
        sourceURL: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.memo = memo
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ReferencePhoto {
    var id: UUID = UUID()
    var referenceID: UUID = UUID()
    var sortOrder: Int = 0
    @Attribute(.externalStorage) var imageData: Data = Data()

    init(id: UUID = UUID(), referenceID: UUID, sortOrder: Int, imageData: Data) {
        self.id = id
        self.referenceID = referenceID
        self.sortOrder = sortOrder
        self.imageData = imageData
    }
}
