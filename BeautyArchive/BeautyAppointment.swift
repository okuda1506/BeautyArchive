import Foundation
import SwiftData

@Model
final class BeautyAppointment {
    var id: UUID = UUID()
    var title: String = ""
    var startAt: Date = Date.now
    var endAt: Date = Date.now
    var shopName: String = ""
    var note: String = ""
    var statusRaw: String = "booked"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        title: String,
        startAt: Date,
        endAt: Date,
        shopName: String = "",
        note: String = "",
        statusRaw: String = "booked",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.shopName = shopName
        self.note = note
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isCancelled: Bool { statusRaw == "cancelled" }
}

@Model
final class AppointmentTreatment {
    var id: UUID = UUID()
    var appointmentID: UUID = UUID()
    var name: String = ""

    init(id: UUID = UUID(), appointmentID: UUID, name: String) {
        self.id = id
        self.appointmentID = appointmentID
        self.name = name
    }
}
