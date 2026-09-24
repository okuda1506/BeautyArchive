import CryptoKit
import Foundation
import Security

struct GoogleOAuthConfiguration {
    let clientID: String
    let callbackScheme: String

    init(clientID: String) throws {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            throw GoogleOAuthError.invalidClientID
        }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty,
              prefix.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw GoogleOAuthError.invalidClientID
        }
        self.clientID = clientID
        self.callbackScheme = "com.googleusercontent.apps.\(prefix)"
    }

    var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
}

struct GoogleOAuthAttempt {
    let authorizationURL: URL
    let codeVerifier: String
    let state: String
}

struct GoogleOAuthTokens {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var needsRefresh: Bool { expiresAt <= Date.now.addingTimeInterval(60) }
}

struct GoogleAccountIdentity {
    let subject: String
    let email: String?
}

enum GoogleOAuthError: LocalizedError {
    case invalidClientID
    case randomFailure
    case invalidCallback
    case stateMismatch
    case authorizationDenied
    case authorizationFailed
    case missingCode
    case missingRefreshToken
    case unauthorized
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidClientID: "Google連携の設定が完了していません。"
        case .randomFailure: "安全な認可情報を作成できませんでした。"
        case .invalidCallback: "Googleからの認可結果を確認できませんでした。"
        case .stateMismatch: "認可結果を安全に確認できませんでした。"
        case .authorizationDenied: "Googleカレンダーへのアクセスが許可されませんでした。"
        case .authorizationFailed: "Googleカレンダーの認可を完了できませんでした。"
        case .missingCode: "Googleから認可コードを受け取れませんでした。"
        case .missingRefreshToken: "Googleカレンダーとの再連携が必要です。"
        case .unauthorized: "Googleカレンダーの認可が切れました。再連携してください。"
        case .httpStatus(let status): "Googleの認可処理に失敗しました（HTTP \(status)）。"
        case .invalidResponse: "Googleの認可応答を読み取れませんでした。"
        }
    }
}

struct GoogleOAuthCore {
    private let configuration: GoogleOAuthConfiguration
    private let session: URLSession

    init(configuration: GoogleOAuthConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func makeAuthorizationAttempt() throws -> GoogleOAuthAttempt {
        let verifier = try randomURLSafeString(byteCount: 32)
        let state = try randomURLSafeString(byteCount: 24)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "accounts.google.com"
        components.path = "/o/oauth2/v2/auth"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: [
                "openid", "email", "https://www.googleapis.com/auth/calendar.events"
            ].joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw GoogleOAuthError.invalidResponse }
        return GoogleOAuthAttempt(
            authorizationURL: url, codeVerifier: verifier, state: state
        )
    }

    func authorizationCode(
        from callback: URL,
        attempt: GoogleOAuthAttempt
    ) throws -> String {
        guard callback.scheme?.lowercased() == configuration.callbackScheme.lowercased(),
              callback.host == nil,
              callback.path == "/oauth2redirect",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw GoogleOAuthError.invalidCallback }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }.compactMap(\.value)
        guard states.count == 1, states[0] == attempt.state else {
            throw GoogleOAuthError.stateMismatch
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw error == "access_denied"
                ? GoogleOAuthError.authorizationDenied
                : GoogleOAuthError.authorizationFailed
        }
        let codes = items.filter { $0.name == "code" }.compactMap(\.value)
        guard codes.count == 1, !codes[0].isEmpty else {
            throw GoogleOAuthError.missingCode
        }
        return codes[0]
    }

    func exchangeCode(
        _ code: String,
        attempt: GoogleOAuthAttempt
    ) async throws -> GoogleOAuthTokens {
        guard !code.isEmpty else { throw GoogleOAuthError.missingCode }
        let data = try await postToken([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: attempt.codeVerifier),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ])
        return try decodeTokens(data, previousRefreshToken: nil)
    }

    func refresh(
        using refreshToken: String
    ) async throws -> GoogleOAuthTokens {
        guard !refreshToken.isEmpty else { throw GoogleOAuthError.missingRefreshToken }
        let data = try await postToken([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ])
        return try decodeTokens(data, previousRefreshToken: refreshToken)
    }

    func identity(using accessToken: String) async throws -> GoogleAccountIdentity {
        guard !accessToken.isEmpty else { throw GoogleOAuthError.unauthorized }
        guard let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else {
            throw GoogleOAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try checkHTTP(response)
        let info: UserInfoResponse
        do {
            info = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        } catch {
            throw GoogleOAuthError.invalidResponse
        }
        guard !info.sub.isEmpty else { throw GoogleOAuthError.invalidResponse }
        return GoogleAccountIdentity(subject: info.sub, email: info.email)
    }

    private func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw GoogleOAuthError.randomFailure
        }
        return Data(bytes).base64URLEncodedString()
    }

    private func postToken(_ items: [URLQueryItem]) async throws -> Data {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthError.invalidResponse
        }
        var components = URLComponents()
        components.queryItems = items
        guard let form = components.percentEncodedQuery?.data(using: .utf8) else {
            throw GoogleOAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = form
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await session.data(for: request)
        try checkHTTP(response)
        return data
    }

    private func checkHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw GoogleOAuthError.invalidResponse
        }
        if response.statusCode == 401 { throw GoogleOAuthError.unauthorized }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleOAuthError.httpStatus(response.statusCode)
        }
    }

    private func decodeTokens(
        _ data: Data,
        previousRefreshToken: String?
    ) throws -> GoogleOAuthTokens {
        let response: TokenResponse
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            response = try decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleOAuthError.invalidResponse
        }
        guard !response.accessToken.isEmpty, response.expiresIn > 0,
              response.tokenType.lowercased() == "bearer" else {
            throw GoogleOAuthError.invalidResponse
        }
        return GoogleOAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previousRefreshToken,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(response.expiresIn))
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
}

private struct UserInfoResponse: Decodable {
    let sub: String
    let email: String?
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
