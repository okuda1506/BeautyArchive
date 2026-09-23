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
    private static func latestByName(
        visits: [SalonVisit],
        treatments: [SalonTreatment]
    ) -> [String: (visit: SalonVisit, treatment: SalonTreatment)] {
        let visitsByID = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
        var latest: [String: (visit: SalonVisit, treatment: SalonTreatment)] = [:]

        for treatment in treatments {
            guard let visit = visitsByID[treatment.visitID] else { continue }
            let key = treatment.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
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
        calendar: Calendar = .current
    ) -> [HomeAction] {
        latestByName(visits: visits, treatments: treatments).values.compactMap { pair in
            let visit = pair.visit
            let treatment = pair.treatment
            guard let dueDate = calendar.date(
                byAdding: .day,
                value: max(1, treatment.cycleDays),
                to: calendar.startOfDay(for: visit.date)
            ) else { return nil }
            let components = URLComponents(string: visit.bookingURL)
            let bookingURL: URL? = ["https", "http"].contains(components?.scheme?.lowercased() ?? "")
                ? components?.url : nil
            return HomeAction(
                id: treatment.id,
                kind: .salonNeedsBooking,
                title: treatment.name,
                date: dueDate,
                detail: visit.salonName.isEmpty ? nil : visit.salonName,
                destinationURL: bookingURL
            )
        }
        .sorted { $0.date < $1.date }
    }
}
