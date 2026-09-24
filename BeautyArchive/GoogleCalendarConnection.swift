import Foundation
import UIKit

extension Notification.Name {
    static let googleCalendarConnectionChanged = Notification.Name(
        "BONEGoogleCalendarConnectionChanged"
    )
}

@MainActor
final class GoogleCalendarConnection {
    static let shared = GoogleCalendarConnection()

    private let configuration: GoogleOAuthConfiguration?
    private let oauth: GoogleOAuthCore?
    private let credentials: GoogleCredentialManager?

    var isConfigured: Bool { configuration != nil }

    private init(bundle: Bundle = .main) {
        guard let clientID = bundle.object(forInfoDictionaryKey: "BONEGoogleOAuthClientID") as? String,
              let configuration = try? GoogleOAuthConfiguration(clientID: clientID),
              let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]],
              urlTypes.contains(where: {
                  ($0["CFBundleURLSchemes"] as? [String])?.contains(configuration.callbackScheme)
                    == true
              }) else {
            self.configuration = nil
            self.oauth = nil
            self.credentials = nil
            return
        }
        self.configuration = configuration
        let oauth = GoogleOAuthCore(configuration: configuration)
        self.oauth = oauth
        self.credentials = GoogleCredentialManager(oauth: oauth)
    }

    func currentAccount() async throws -> GoogleAccountIdentity? {
        guard let credentials else { throw GoogleOAuthError.invalidClientID }
        return try await credentials.currentAccount()
    }

    func accessToken() async throws -> String {
        guard let credentials else { throw GoogleOAuthError.invalidClientID }
        return try await credentials.accessToken()
    }

    func connect(anchor: UIWindow) async throws -> GoogleAccountIdentity {
        guard let configuration, let oauth, let credentials else {
            throw GoogleOAuthError.invalidClientID
        }
        let browser = SystemGoogleOAuthBrowser(anchor: anchor)
        let flow = GoogleOAuthAuthorizationFlow(
            configuration: configuration, core: oauth, browser: browser
        )
        let result = try await flow.authorize()
        try await credentials.connect(identity: result.identity, tokens: result.tokens)
        NotificationCenter.default.post(name: .googleCalendarConnectionChanged, object: nil)
        return result.identity
    }

    func disconnect() async throws {
        guard let credentials else { throw GoogleOAuthError.invalidClientID }
        try await credentials.disconnect()
        NotificationCenter.default.post(name: .googleCalendarConnectionChanged, object: nil)
    }
}
