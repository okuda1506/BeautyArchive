import Foundation

struct HomeAction: Identifiable {
    enum Kind: Equatable {
        case salonNeedsBooking
        case salonBooked
        case itemReplacement
    }

    let id: UUID
    let kind: Kind
    let title: String
    let date: Date
    let imageName: String?
    let imageData: Data?
    let detail: String?
    let destinationURL: URL?

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        date: Date,
        imageName: String? = nil,
        imageData: Data? = nil,
        detail: String? = nil,
        destinationURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.imageName = imageName
        self.imageData = imageData
        self.detail = detail
        self.destinationURL = destinationURL
    }

    static func upcoming(from actions: [HomeAction], limit: Int = 3) -> [HomeAction] {
        Array(actions.sorted { $0.date < $1.date }.prefix(max(0, limit)))
    }

    func daysUntil(referenceDate: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: referenceDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}
