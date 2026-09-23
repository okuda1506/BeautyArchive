import Foundation
import SwiftData

@Model
final class SalonPhoto {
    var id: UUID = UUID()
    var visitID: UUID = UUID()
    var sortOrder: Int = 0
    @Attribute(.externalStorage) var imageData: Data = Data()

    init(id: UUID = UUID(), visitID: UUID, sortOrder: Int, imageData: Data) {
        self.id = id
        self.visitID = visitID
        self.sortOrder = sortOrder
        self.imageData = imageData
    }
}
