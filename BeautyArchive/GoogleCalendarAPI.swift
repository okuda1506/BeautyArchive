import Foundation

struct GoogleCalendarEvent: Identifiable, Equatable {
    let remoteID: String
    let calendarID: String
    let title: String
    let startAt: Date
    let endAt: Date
    let isAllDay: Bool
    let webURL: URL?

    var id: String { "\(calendarID):\(remoteID)" }
}

enum GoogleCalendarAPIError: LocalizedError {
    case invalidRange
    case invalidCalendarID
    case missingAccessToken
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    case repeatedPageToken

    var errorDescription: String? {
        switch self {
        case .invalidRange: "予定の取得期間が正しくありません。"
        case .invalidCalendarID: "Googleカレンダーを特定できません。"
        case .missingAccessToken: "Googleカレンダーとの連携が必要です。"
        case .unauthorized: "Googleカレンダーの認可が切れました。再連携してください。"
        case .httpStatus(let status): "Googleカレンダーの取得に失敗しました（HTTP \(status)）。"
        case .invalidResponse: "Googleカレンダーの応答を読み取れませんでした。"
        case .repeatedPageToken: "Googleカレンダーの予定を最後まで取得できませんでした。"
        }
    }
}

struct GoogleCalendarAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func events(
        calendarID: String,
        from start: Date,
        to end: Date,
        accessToken: String
    ) async throws -> [GoogleCalendarEvent] {
        guard start < end else { throw GoogleCalendarAPIError.invalidRange }
        guard !calendarID.isEmpty else { throw GoogleCalendarAPIError.invalidCalendarID }
        guard !accessToken.isEmpty else { throw GoogleCalendarAPIError.missingAccessToken }

        var allEvents: [GoogleCalendarEvent] = []
        var pageToken: String?
        var seenTokens: Set<String> = []

        repeat {
            let url = try eventsURL(calendarID: calendarID, from: start, to: end, pageToken: pageToken)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GoogleCalendarAPIError.invalidResponse
            }
            switch response.statusCode {
            case 200..<300: break
            case 401: throw GoogleCalendarAPIError.unauthorized
            default: throw GoogleCalendarAPIError.httpStatus(response.statusCode)
            }

            let page = try decodePage(data, calendarID: calendarID)
            allEvents.append(contentsOf: page.events)
            if let next = page.nextPageToken, !next.isEmpty {
                guard seenTokens.insert(next).inserted else {
                    throw GoogleCalendarAPIError.repeatedPageToken
                }
                pageToken = next
            } else {
                pageToken = nil
            }
        } while pageToken != nil

        return allEvents.sorted {
            if $0.startAt == $1.startAt { return $0.id < $1.id }
            return $0.startAt < $1.startAt
        }
    }

    func eventsURL(
        calendarID: String,
        from start: Date,
        to end: Date,
        pageToken: String? = nil
    ) throws -> URL {
        guard start < end else { throw GoogleCalendarAPIError.invalidRange }
        guard !calendarID.isEmpty else { throw GoogleCalendarAPIError.invalidCalendarID }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%")
        guard let escapedID = calendarID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw GoogleCalendarAPIError.invalidCalendarID
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/calendar/v3/calendars/\(escapedID)/events"
        let formatter = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        guard let url = components.url else { throw GoogleCalendarAPIError.invalidResponse }
        return url
    }

    func decodePage(
        _ data: Data,
        calendarID: String,
        calendar: Calendar = .current
    ) throws -> (events: [GoogleCalendarEvent], nextPageToken: String?) {
        let page: EventPage
        do {
            page = try JSONDecoder().decode(EventPage.self, from: data)
        } catch {
            throw GoogleCalendarAPIError.invalidResponse
        }
        let events = (page.items ?? []).compactMap { item -> GoogleCalendarEvent? in
            guard item.status != "cancelled",
                  let id = item.id, !id.isEmpty,
                  let start = item.start, let end = item.end,
                  (start.date != nil) == (end.date != nil),
                  let startValue = parse(start, calendar: calendar),
                  let endValue = parse(end, calendar: calendar),
                  endValue > startValue
            else { return nil }
            return GoogleCalendarEvent(
                remoteID: id,
                calendarID: calendarID,
                title: item.summary.flatMap { $0.isEmpty ? nil : $0 } ?? "無題の予定",
                startAt: startValue,
                endAt: endValue,
                isAllDay: start.date != nil,
                webURL: item.htmlLink.flatMap(URL.init(string:))
            )
        }
        return (events, page.nextPageToken)
    }

    private func parse(_ value: EventTime, calendar: Calendar) -> Date? {
        if let dateTime = value.dateTime {
            let timeSuffix = dateTime.dropFirst(19)
            let hasOffset = timeSuffix.contains("Z")
                || timeSuffix.contains("+") || timeSuffix.contains("-")
            if !hasOffset {
                guard let timeZoneID = value.timeZone,
                      let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.isLenient = false
                formatter.dateFormat = dateTime.contains(".")
                    ? "yyyy-MM-dd'T'HH:mm:ss.SSS"
                    : "yyyy-MM-dd'T'HH:mm:ss"
                return formatter.date(from: dateTime)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTime) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateTime)
        }
        guard let date = value.date else { return nil }
        let components = date.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        guard let parsed = localCalendar.date(from: DateComponents(
            year: components[0], month: components[1], day: components[2]
        )) else { return nil }
        let parsedComponents = localCalendar.dateComponents([.year, .month, .day], from: parsed)
        guard parsedComponents.year == components[0],
              parsedComponents.month == components[1],
              parsedComponents.day == components[2] else { return nil }
        return parsed
    }
}

private struct EventPage: Decodable {
    let items: [EventItem]?
    let nextPageToken: String?
}

private struct EventItem: Decodable {
    let id: String?
    let status: String?
    let summary: String?
    let start: EventTime?
    let end: EventTime?
    let htmlLink: String?
}

private struct EventTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}
