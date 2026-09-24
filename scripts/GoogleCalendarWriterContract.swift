import Foundation

private final class MockURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let body: Data

        init(_ status: Int, _ json: String = "") {
            self.status = status
            self.body = Data(json.utf8)
        }
    }

    private static let lock = NSLock()
    private static var responses: [Response] = []
    private static var recorded: [URLRequest] = []

    static func prepare(_ responses: [Response]) {
        lock.lock()
        self.responses = responses
        recorded = []
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        let result = recorded
        lock.unlock()
        return result
    }

    static func hasUnconsumedResponses() -> Bool {
        lock.lock()
        let result = !responses.isEmpty
        lock.unlock()
        return result
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer[..<count])
            }
            captured.httpBody = body
        }
        Self.lock.lock()
        Self.recorded.append(captured)
        let next = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()
        guard let next, let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: next.status, httpVersion: nil, headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !next.body.isEmpty { client?.urlProtocol(self, didLoad: next.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum ContractFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message): message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ContractFailure.expectation(message) }
}

private func json(_ request: URLRequest) throws -> [String: Any] {
    guard let data = request.httpBody,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ContractFailure.expectation("Request JSON body is missing")
    }
    return object
}

private func requestMethod(_ request: URLRequest, _ method: String, _ path: String) throws {
    try require(request.httpMethod == method, "Expected \(method) request")
    try require(request.url?.path == path, "Unexpected request path")
    try require(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
                "Access token header missing")
}

@main
private enum GoogleCalendarWriterContract {
    static func main() async throws {
        guard let appointmentID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF") else {
            throw ContractFailure.expectation("Fixture UUID is invalid")
        }
        let appointment = GoogleCalendarAppointment(
            id: appointmentID,
            title: "カット", startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            shopName: "Salon", note: "短め"
        )
        let eventPath = "/calendar/v3/calendars/primary/events"
        let itemPath = "\(eventPath)/\(appointment.eventID)"
        let owned = """
            {"id":"\(appointment.eventID)","etag":"\\"v1\\"",\
            "extendedProperties":{"private":{"boneAppointmentID":"\(appointment.ownerMarker)"}}}
            """
        let foreign = """
            {"id":"\(appointment.eventID)","etag":"\\"v1\\"",\
            "extendedProperties":{"private":{"boneAppointmentID":"00000000-0000-0000-0000-000000000000"}}}
            """

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let writer = GoogleCalendarWriter(session: session)

        MockURLProtocol.prepare([.init(200, "{\"id\":\"\(appointment.eventID)\"}")])
        let created = try await writer.create(
            appointment, calendarID: "primary", accessToken: "test-token"
        )
        try require(created == appointment.eventID, "Create returned another event ID")
        var requests = MockURLProtocol.requests()
        try require(requests.count == 1, "Create must send one request")
        try requestMethod(requests[0], "POST", eventPath)
        let createBody = try json(requests[0])
        try require(createBody["id"] as? String == appointment.eventID, "Event ID is not deterministic")
        try require(createBody["summary"] as? String == "カット", "Title was not sent")
        let properties = createBody["extendedProperties"] as? [String: Any]
        let privateProperties = properties?["private"] as? [String: String]
        try require(privateProperties?["boneAppointmentID"] == appointment.ownerMarker,
                    "Owner marker was not sent")
        try require(!MockURLProtocol.hasUnconsumedResponses(), "Unused create response")

        MockURLProtocol.prepare([
            .init(409), .init(200, owned), .init(200, "{\"id\":\"\(appointment.eventID)\"}")
        ])
        let retried = try await writer.create(
            appointment, calendarID: "primary", accessToken: "test-token"
        )
        try require(retried == appointment.eventID, "Conflict retry returned another ID")
        requests = MockURLProtocol.requests()
        try require(requests.count == 3, "Conflict retry must POST, GET, then PATCH")
        try requestMethod(requests[0], "POST", eventPath)
        try requestMethod(requests[1], "GET", itemPath)
        try requestMethod(requests[2], "PATCH", itemPath)
        try require(requests[2].value(forHTTPHeaderField: "If-Match") == "\"v1\"",
                    "Update must use the verified ETag")
        try require(!MockURLProtocol.hasUnconsumedResponses(), "Unused conflict response")

        MockURLProtocol.prepare([.init(409), .init(200, foreign)])
        do {
            _ = try await writer.create(
                appointment, calendarID: "primary", accessToken: "test-token"
            )
            throw ContractFailure.expectation("Foreign event was overwritten")
        } catch GoogleCalendarWriteError.foreignEvent {
            try require(MockURLProtocol.requests().count == 2,
                        "Foreign event must not receive PATCH")
        }

        MockURLProtocol.prepare([.init(200, owned), .init(204)])
        try await writer.delete(appointment, calendarID: "primary", accessToken: "test-token")
        requests = MockURLProtocol.requests()
        try require(requests.count == 2, "Delete must verify ownership first")
        try requestMethod(requests[0], "GET", itemPath)
        try requestMethod(requests[1], "DELETE", itemPath)
        try require(requests[1].value(forHTTPHeaderField: "If-Match") == "\"v1\"",
                    "Delete must use the verified ETag")
        try require(!MockURLProtocol.hasUnconsumedResponses(), "Unused delete response")

        print("Google Calendar write contract checks passed")
    }
}
