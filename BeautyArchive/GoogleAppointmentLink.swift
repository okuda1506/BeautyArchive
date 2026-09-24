import Foundation
import SwiftData

enum GoogleAppointmentSyncState: String {
    case pendingUpsert
    case pendingDelete
    case synced
    case failedUpsert
    case failedDelete

    var needsSync: Bool { self == .pendingUpsert || self == .pendingDelete }
    var isDeletion: Bool { self == .pendingDelete || self == .failedDelete }

    var title: String {
        switch self {
        case .pendingUpsert: "Googleへの反映待ち"
        case .pendingDelete: "Googleからの削除待ち"
        case .synced: "Googleに反映済み"
        case .failedUpsert: "Googleへの反映に失敗"
        case .failedDelete: "Googleからの削除に失敗"
        }
    }
}

@Model
final class GoogleAppointmentLink {
    var id: UUID = UUID()
    var appointmentID: UUID = UUID()
    var accountSubject: String = ""
    var calendarID: String = "primary"
    var eventID: String = ""
    var title: String = ""
    var startAt: Date = Date.now
    var endAt: Date = Date.now
    var shopName: String = ""
    var note: String = ""
    var stateRaw: String = GoogleAppointmentSyncState.pendingUpsert.rawValue
    var lastError: String? = nil
    var revision: UUID = UUID()
    var updatedAt: Date = Date.now

    init(appointment: BeautyAppointment, accountSubject: String) {
        self.appointmentID = appointment.id
        self.accountSubject = accountSubject
        self.eventID = GoogleCalendarEventIdentity.eventID(for: appointment.id)
        update(from: appointment)
    }

    var state: GoogleAppointmentSyncState {
        GoogleAppointmentSyncState(rawValue: stateRaw) ?? .failedUpsert
    }

    var calendarAppointment: GoogleCalendarAppointment {
        GoogleCalendarAppointment(
            id: appointmentID, title: title, startAt: startAt, endAt: endAt,
            shopName: shopName, note: note
        )
    }

    func update(from appointment: BeautyAppointment) {
        title = appointment.title
        startAt = appointment.startAt
        endAt = appointment.endAt
        shopName = appointment.shopName
        note = appointment.note
        stateRaw = GoogleAppointmentSyncState.pendingUpsert.rawValue
        lastError = nil
        revision = UUID()
        updatedAt = .now
    }

    func markForDeletion() {
        stateRaw = GoogleAppointmentSyncState.pendingDelete.rawValue
        lastError = nil
        revision = UUID()
        updatedAt = .now
    }
}
