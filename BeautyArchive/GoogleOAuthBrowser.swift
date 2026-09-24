import AuthenticationServices
import Foundation

struct GoogleOAuthAuthorizationResult {
    let identity: GoogleAccountIdentity
    let tokens: GoogleOAuthTokens
}

@MainActor
protocol GoogleOAuthBrowserOpening {
    func open(_ url: URL, callbackScheme: String) async throws -> URL
}

enum GoogleOAuthBrowserError: LocalizedError {
    case alreadyInProgress
    case cannotStart
    case cancelled
    case missingCallback
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            "Googleの認可画面がすでに開いています。"
        case .cannotStart:
            "Googleの認可画面を開けませんでした。"
        case .cancelled:
            "Googleカレンダーの連携をキャンセルしました。"
        case .missingCallback:
            "Googleから認可結果を受け取れませんでした。"
        case .system(let error):
            error.localizedDescription
        }
    }
}

@MainActor
struct GoogleOAuthAuthorizationFlow {
    private let configuration: GoogleOAuthConfiguration
    private let core: GoogleOAuthCore
    private let browser: any GoogleOAuthBrowserOpening

    init(
        configuration: GoogleOAuthConfiguration,
        core: GoogleOAuthCore,
        browser: any GoogleOAuthBrowserOpening
    ) {
        self.configuration = configuration
        self.core = core
        self.browser = browser
    }

    func authorize() async throws -> GoogleOAuthAuthorizationResult {
        let attempt = try core.makeAuthorizationAttempt()
        let callback = try await browser.open(
            attempt.authorizationURL, callbackScheme: configuration.callbackScheme
        )
        let code = try core.authorizationCode(from: callback, attempt: attempt)
        let tokens = try await core.exchangeCode(code, attempt: attempt)
        let identity = try await core.identity(using: tokens.accessToken)
        return GoogleOAuthAuthorizationResult(identity: identity, tokens: tokens)
    }
}

@MainActor
final class SystemGoogleOAuthBrowser: NSObject,
    GoogleOAuthBrowserOpening, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?
    private var pending: CheckedContinuation<URL, Error>?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func open(_ url: URL, callbackScheme: String) async throws -> URL {
        guard pending == nil else { throw GoogleOAuthBrowserError.alreadyInProgress }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: callbackScheme
                ) { callback, error in
                    Task { @MainActor in
                        self.complete(callback: callback, error: error)
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                if !session.start() {
                    complete(callback: nil, error: GoogleOAuthBrowserError.cannotStart)
                }
            }
        } onCancel: {
            Task { @MainActor in self.session?.cancel() }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    private func complete(callback: URL?, error: Error?) {
        guard let pending else { return }
        self.pending = nil
        session = nil
        if let error {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                pending.resume(throwing: GoogleOAuthBrowserError.cancelled)
            } else if let browserError = error as? GoogleOAuthBrowserError {
                pending.resume(throwing: browserError)
            } else {
                pending.resume(throwing: GoogleOAuthBrowserError.system(error))
            }
        } else if let callback {
            pending.resume(returning: callback)
        } else {
            pending.resume(throwing: GoogleOAuthBrowserError.missingCallback)
        }
    }
}
