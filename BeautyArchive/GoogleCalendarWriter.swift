import Foundation

struct GoogleCalendarAppointment {
    let id: UUID
    let title: String
    let startAt: Date
    let endAt: Date
    let shopName: String
    let note: String

    var eventID: String {
        GoogleCalendarEventIdentity.eventID(for: id)
    }

    var ownerMarker: String { id.uuidString.lowercased() }
}

enum GoogleCalendarEventIdentity {
    static func eventID(for appointmentID: UUID) -> String {
        "bone" + appointmentID.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    static func appointmentID(eventID: String, ownerMarker: String?) -> UUID? {
        guard let ownerMarker,
              let appointmentID = UUID(uuidString: ownerMarker),
              ownerMarker == appointmentID.uuidString.lowercased(),
              eventID == self.eventID(for: appointmentID) else { return nil }
        return appointmentID
    }
}

enum GoogleCalendarWriteError: LocalizedError {
    case invalidAppointment
    case invalidCalendarID
    case missingAccessToken
    case unauthorized
    case notFound
    case foreignEvent
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidAppointment: "美容予定の名前と日時を確認してください。"
        case .invalidCalendarID: "Googleカレンダーを特定できません。"
        case .missingAccessToken: "Googleカレンダーとの連携が必要です。"
        case .unauthorized: "Googleカレンダーの認可が切れました。再連携してください。"
        case .notFound: "Googleカレンダー上の対応する予定が見つかりません。"
        case .foreignEvent: "Googleカレンダー上の別の予定を変更しないため、反映を中止しました。"
        case .httpStatus(let status): "Googleカレンダーへの反映に失敗しました（HTTP \(status)）。"
        case .invalidResponse: "Googleカレンダーの応答を読み取れませんでした。"
        }
    }
}

struct GoogleCalendarWriter {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func create(
        _ appointment: GoogleCalendarAppointment,
        calendarID: String,
        accessToken: String
    ) async throws -> String {
        try validate(appointment)
        let url = try eventURL(calendarID: calendarID)
        let payload = eventPayload(appointment, includeIdentity: true)
        let result = try await send(
            "POST", to: url, accessToken: accessToken,
            body: try JSONEncoder().encode(payload)
        )
        if result.status == 409 {
            // A retry can reach an event created before the previous response was lost.
            return try await update(appointment, calendarID: calendarID, accessToken: accessToken)
        }
        try checkSuccess(result.status)
        let response = try decodeEvent(result.data)
        guard response.id == appointment.eventID else {
            throw GoogleCalendarWriteError.invalidResponse
        }
        return appointment.eventID
    }

    func update(
        _ appointment: GoogleCalendarAppointment,
        calendarID: String,
        accessToken: String
    ) async throws -> String {
        try validate(appointment)
        let url = try eventURL(calendarID: calendarID, eventID: appointment.eventID)
        let etag = try await verifiedETag(
            appointment, at: url, accessToken: accessToken
        )
        let payload = eventPayload(appointment, includeIdentity: false)
        let result = try await send(
            "PATCH", to: url, accessToken: accessToken,
            body: try JSONEncoder().encode(payload), ifMatch: etag
        )
        try checkSuccess(result.status)
        let response = try decodeEvent(result.data)
        guard response.id == appointment.eventID else {
            throw GoogleCalendarWriteError.invalidResponse
        }
        return appointment.eventID
    }

    func delete(
        _ appointment: GoogleCalendarAppointment,
        calendarID: String,
        accessToken: String
    ) async throws {
        let url = try eventURL(calendarID: calendarID, eventID: appointment.eventID)
        let etag = try await verifiedETag(
            appointment, at: url, accessToken: accessToken
        )
        let result = try await send(
            "DELETE", to: url, accessToken: accessToken, ifMatch: etag
        )
        try checkSuccess(result.status)
    }

    private func validate(_ appointment: GoogleCalendarAppointment) throws {
        guard !appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              appointment.startAt < appointment.endAt else {
            throw GoogleCalendarWriteError.invalidAppointment
        }
    }

    private func eventURL(calendarID: String, eventID: String? = nil) throws -> URL {
        guard !calendarID.isEmpty else { throw GoogleCalendarWriteError.invalidCalendarID }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%")
        guard let escapedID = calendarID.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw GoogleCalendarWriteError.invalidCalendarID
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/calendar/v3/calendars/\(escapedID)/events"
        if let eventID { components.percentEncodedPath += "/\(eventID)" }
        guard let url = components.url else { throw GoogleCalendarWriteError.invalidResponse }
        return url
    }

    private func eventPayload(
        _ appointment: GoogleCalendarAppointment,
        includeIdentity: Bool
    ) -> EventPayload {
        let formatter = ISO8601DateFormatter()
        return EventPayload(
            id: includeIdentity ? appointment.eventID : nil,
            summary: appointment.title.trimmingCharacters(in: .whitespacesAndNewlines),
            location: appointment.shopName,
            description: appointment.note,
            start: EventDateTime(dateTime: formatter.string(from: appointment.startAt)),
            end: EventDateTime(dateTime: formatter.string(from: appointment.endAt)),
            extendedProperties: includeIdentity
                ? EventExtendedProperties(privateValues: [
                    "boneAppointmentID": appointment.ownerMarker
                ])
                : nil
        )
    }

    private func verifiedETag(
        _ appointment: GoogleCalendarAppointment,
        at url: URL,
        accessToken: String
    ) async throws -> String {
        let result = try await send("GET", to: url, accessToken: accessToken)
        if result.status == 404 { throw GoogleCalendarWriteError.notFound }
        try checkSuccess(result.status)
        let response = try decodeEvent(result.data)
        guard response.id == appointment.eventID,
              response.extendedProperties?.privateValues?["boneAppointmentID"]
                == appointment.ownerMarker else {
            throw GoogleCalendarWriteError.foreignEvent
        }
        guard let etag = response.etag, !etag.isEmpty else {
            throw GoogleCalendarWriteError.invalidResponse
        }
        return etag
    }

    private func send(
        _ method: String,
        to url: URL,
        accessToken: String,
        body: Data? = nil,
        ifMatch: String? = nil
    ) async throws -> (status: Int, data: Data) {
        guard !accessToken.isEmpty else { throw GoogleCalendarWriteError.missingAccessToken }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let ifMatch { request.setValue(ifMatch, forHTTPHeaderField: "If-Match") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GoogleCalendarWriteError.invalidResponse
        }
        if response.statusCode == 401 { throw GoogleCalendarWriteError.unauthorized }
        return (response.statusCode, data)
    }

    private func checkSuccess(_ status: Int) throws {
        guard (200..<300).contains(status) else {
            throw GoogleCalendarWriteError.httpStatus(status)
        }
    }

    private func decodeEvent(_ data: Data) throws -> EventResponse {
        do {
            return try JSONDecoder().decode(EventResponse.self, from: data)
        } catch {
            throw GoogleCalendarWriteError.invalidResponse
        }
    }
}

private struct EventDateTime: Encodable {
    let dateTime: String
}

private struct EventPayload: Encodable {
    let id: String?
    let summary: String
    let location: String
    let description: String
    let start: EventDateTime
    let end: EventDateTime
    let extendedProperties: EventExtendedProperties?
}

private struct EventExtendedProperties: Codable {
    let privateValues: [String: String]?

    enum CodingKeys: String, CodingKey {
        case privateValues = "private"
    }
}

private struct EventResponse: Decodable {
    let id: String?
    let etag: String?
    let extendedProperties: EventExtendedProperties?
}
