import Foundation
import SwiftData

@Model
final class SalonVisit {
    var id: UUID = UUID()
    var date: Date = Date.now
    var salonName: String = ""
    var stylistName: String = ""
    var orderNote: String = ""
    var impression: String = ""
    var nextVisitNote: String = ""
    var bookingURL: String = ""
    var price: Int? = nil

    init(
        id: UUID = UUID(),
        date: Date = .now,
        salonName: String = "",
        stylistName: String = "",
        orderNote: String = "",
        impression: String = "",
        nextVisitNote: String = "",
        bookingURL: String = "",
        price: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.salonName = salonName
        self.stylistName = stylistName
        self.orderNote = orderNote
        self.impression = impression
        self.nextVisitNote = nextVisitNote
        self.bookingURL = bookingURL
        self.price = price
    }
}

@Model
final class SalonTreatment {
    var id: UUID = UUID()
    var visitID: UUID = UUID()
    var name: String = ""
    var cycleDays: Int = 45

    init(id: UUID = UUID(), visitID: UUID, name: String, cycleDays: Int) {
        self.id = id
        self.visitID = visitID
        self.name = name
        self.cycleDays = cycleDays
    }
}

struct SalonTreatmentChoice: Identifiable {
    let id: String
    let name: String
    let cycleDays: Int
}

enum SalonMaintenance {
    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
    }

    private static func latestByName(
        visits: [SalonVisit],
        treatments: [SalonTreatment]
    ) -> [String: (visit: SalonVisit, treatment: SalonTreatment)] {
        let visitsByID = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
        var latest: [String: (visit: SalonVisit, treatment: SalonTreatment)] = [:]

        for treatment in treatments {
            guard let visit = visitsByID[treatment.visitID] else { continue }
            let key = normalizedName(treatment.name)
            guard !key.isEmpty else { continue }
            if let previous = latest[key] {
                if previous.visit.date > visit.date { continue }
                if previous.visit.date == visit.date,
                   previous.visit.id.uuidString >= visit.id.uuidString { continue }
            }
            latest[key] = (visit, treatment)
        }
        return latest
    }

    static func treatmentChoices(
        visits: [SalonVisit],
        treatments: [SalonTreatment]
    ) -> [SalonTreatmentChoice] {
        latestByName(visits: visits, treatments: treatments).map { entry in
            SalonTreatmentChoice(
                id: entry.key,
                name: entry.value.treatment.name,
                cycleDays: entry.value.treatment.cycleDays
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func actions(
        visits: [SalonVisit],
        treatments: [SalonTreatment],
        photos: [SalonPhoto] = [],
        appointments: [BeautyAppointment] = [],
        appointmentTreatments: [AppointmentTreatment] = [],
        reminderAdjustments: [SalonReminderAdjustment] = [],
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [HomeAction] {
        let latest = latestByName(visits: visits, treatments: treatments)
        let firstPhotoByVisit = Dictionary(grouping: photos, by: \.visitID)
            .compactMapValues { group in
                group.min { $0.sortOrder < $1.sortOrder }?.imageData
            }
        let namesByAppointment = Dictionary(grouping: appointmentTreatments, by: \.appointmentID)
        let adjustmentsByTreatment = Dictionary(grouping: reminderAdjustments, by: \.treatmentID)
        var reservedNames: Set<String> = []
        let appointmentActions: [HomeAction] = appointments.compactMap { appointment in
            guard !appointment.isCancelled else { return nil }
            guard appointment.completedVisitID == nil
                || !visits.contains(where: { $0.id == appointment.completedVisitID })
            else { return nil }
            let names = (namesByAppointment[appointment.id] ?? []).map(\.name)
                .filter { !normalizedName($0).isEmpty }
            guard !names.isEmpty else { return nil }
            reservedNames.formUnion(names.map { normalizedName($0) })
            let firstRelatedVisit = names.compactMap { latest[normalizedName($0)]?.visit }.first
            return HomeAction(
                id: appointment.id,
                kind: appointment.startAt >= referenceDate ? .salonBooked : .salonNeedsRecord,
                title: names.joined(separator: "・"),
                date: appointment.startAt,
                imageData: firstRelatedVisit.flatMap { firstPhotoByVisit[$0.id] },
                detail: appointment.shopName.isEmpty ? nil : appointment.shopName
            )
        }
        let dueActions: [HomeAction] = latest.compactMap { entry in
            guard !reservedNames.contains(entry.key) else { return nil }
            let pair = entry.value
            let visit = pair.visit
            let treatment = pair.treatment
            guard let dueDate = calendar.date(
                byAdding: .day,
                value: max(1, treatment.cycleDays),
                to: calendar.startOfDay(for: visit.date)
            ) else { return nil }
            let adjustment = adjustmentsByTreatment[treatment.id]?
                .filter { calendar.isDate($0.baseDueDate, inSameDayAs: dueDate) }
                .max { $0.updatedAt < $1.updatedAt }
            let adjustedDate = adjustment?.overrideDueDate ?? dueDate
            let components = URLComponents(string: visit.bookingURL)
            let bookingURL: URL? = ["https", "http"].contains(components?.scheme?.lowercased() ?? "")
                ? components?.url : nil
            let previousDate = visit.date.formatted(
                .dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))
            )
            let detail = visit.salonName.isEmpty
                ? "前回の施術 \(previousDate)"
                : "前回の施術 \(previousDate) · \(visit.salonName)"
            return HomeAction(
                id: treatment.id,
                kind: .salonNeedsBooking,
                title: treatment.name,
                date: adjustedDate,
                imageData: firstPhotoByVisit[visit.id],
                detail: detail,
                destinationURL: bookingURL,
                baselineDate: dueDate,
                snoozedReminderDate: adjustment?.snoozedUntil,
                hasDueDateOverride: adjustment?.overrideDueDate != nil
            )
        }
        return (appointmentActions + dueActions).sorted { $0.date < $1.date }
    }
}
