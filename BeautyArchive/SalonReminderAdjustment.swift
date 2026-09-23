import Foundation
import SwiftData

@Model
final class SalonReminderAdjustment {
    var id: UUID = UUID()
    var treatmentID: UUID = UUID()
    var baseDueDate: Date = Date.now
    var overrideDueDate: Date? = nil
    var snoozedUntil: Date? = nil
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        treatmentID: UUID,
        baseDueDate: Date,
        overrideDueDate: Date? = nil,
        snoozedUntil: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.treatmentID = treatmentID
        self.baseDueDate = baseDueDate
        self.overrideDueDate = overrideDueDate
        self.snoozedUntil = snoozedUntil
        self.updatedAt = updatedAt
    }
}
