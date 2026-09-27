import Foundation

struct HomeAction: Identifiable {
    enum Kind: Equatable {
        case salonNeedsBooking
        case salonBooked
        case salonNeedsRecord
        case itemReplacement
    }

    let id: UUID
    let kind: Kind
    let title: String
    let date: Date
    let imageName: String?
    let imageData: Data?
    let detail: String?
    let visitID: UUID?
    let productID: UUID?
    let destinationURL: URL?
    let baselineDate: Date?
    let snoozedReminderDate: Date?
    let hasDueDateOverride: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        date: Date,
        imageName: String? = nil,
        imageData: Data? = nil,
        detail: String? = nil,
        visitID: UUID? = nil,
        productID: UUID? = nil,
        destinationURL: URL? = nil,
        baselineDate: Date? = nil,
        snoozedReminderDate: Date? = nil,
        hasDueDateOverride: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.imageName = imageName
        self.imageData = imageData
        self.detail = detail
        self.visitID = visitID
        self.productID = productID
        self.destinationURL = destinationURL
        self.baselineDate = baselineDate
        self.snoozedReminderDate = snoozedReminderDate
        self.hasDueDateOverride = hasDueDateOverride
    }

    func daysUntil(referenceDate: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: referenceDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}

struct HomeActionGroups {
    let needsAttention: [HomeAction]
    let withinSevenDays: [HomeAction]
    let later: [HomeAction]

    init(actions: [HomeAction], referenceDate: Date = .now, calendar: Calendar = .current) {
        var needsAttention: [HomeAction] = []
        var withinSevenDays: [HomeAction] = []
        var later: [HomeAction] = []
        for action in actions.sorted(by: { $0.date < $1.date }) {
            let days = action.daysUntil(referenceDate: referenceDate, calendar: calendar)
            if days < 0 || action.kind == .salonNeedsRecord {
                needsAttention.append(action)
            } else if days <= 7 {
                withinSevenDays.append(action)
            } else {
                later.append(action)
            }
        }
        self.needsAttention = needsAttention
        self.withinSevenDays = withinSevenDays
        self.later = later
    }
}
