import Foundation
import Security

nonisolated struct GoogleCredentials: Codable {
    let identity: GoogleAccountIdentity
    let tokens: GoogleOAuthTokens
}

nonisolated protocol GoogleCredentialStorage {
    func load() throws -> GoogleCredentials?
    func save(_ credentials: GoogleCredentials) throws
    func delete() throws
}

nonisolated enum GoogleCredentialError: LocalizedError {
    case keychain(OSStatus)
    case invalidStoredData
    case notConnected
    case refreshInProgress
    case credentialsChanged

    var errorDescription: String? {
        switch self {
        case .keychain:
            "Google連携の認証情報にアクセスできませんでした。"
        case .invalidStoredData:
            "保存したGoogle連携情報を読み取れませんでした。再連携してください。"
        case .notConnected:
            "Googleカレンダーと連携されていません。"
        case .refreshInProgress:
            "Google連携情報を更新中です。少し待ってから再度お試しください。"
        case .credentialsChanged:
            "Google連携情報が変更されました。もう一度お試しください。"
        }
    }
}

nonisolated struct KeychainGoogleCredentialStore: GoogleCredentialStorage {
    private let service = "com.takuyaokuda.BeautyArchive.googleCalendarOAuth"
    private let account = "google-calendar"

    func load() throws -> GoogleCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GoogleCredentialError.keychain(status) }
        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(GoogleCredentials.self, from: data)
        else { throw GoogleCredentialError.invalidStoredData }
        return credentials
    }

    func save(_ credentials: GoogleCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let replacement: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, replacement as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw GoogleCredentialError.keychain(updateStatus)
            }
        } else if status != errSecSuccess {
            throw GoogleCredentialError.keychain(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleCredentialError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

nonisolated protocol GoogleOAuthTokenRefreshing {
    func refresh(using refreshToken: String) async throws -> GoogleOAuthTokens
}

extension GoogleOAuthCore: GoogleOAuthTokenRefreshing {}

actor GoogleCredentialManager {
    private let store: any GoogleCredentialStorage
    private let oauth: any GoogleOAuthTokenRefreshing
    private var refreshTask: Task<String, Error>?

    init(store: any GoogleCredentialStorage = KeychainGoogleCredentialStore(),
         oauth: any GoogleOAuthTokenRefreshing) {
        self.store = store
        self.oauth = oauth
    }

    func currentAccount() throws -> GoogleAccountIdentity? {
        try store.load()?.identity
    }

    func connect(identity: GoogleAccountIdentity, tokens: GoogleOAuthTokens) throws {
        guard refreshTask == nil else { throw GoogleCredentialError.refreshInProgress }
        let previous = try store.load()
        let previousRefreshToken = previous?.identity.subject == identity.subject
            ? previous?.tokens.refreshToken : nil
        guard let refreshToken = tokens.refreshToken ?? previousRefreshToken else {
            throw GoogleOAuthError.missingRefreshToken
        }
        let persistedTokens = GoogleOAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            expiresAt: tokens.expiresAt
        )
        try store.save(GoogleCredentials(identity: identity, tokens: persistedTokens))
    }

    func disconnect() throws {
        guard refreshTask == nil else { throw GoogleCredentialError.refreshInProgress }
        try store.delete()
    }

    func accessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        guard let credentials = try store.load() else {
            throw GoogleCredentialError.notConnected
        }
        if !credentials.tokens.needsRefresh { return credentials.tokens.accessToken }
        guard let refreshToken = credentials.tokens.refreshToken else {
            throw GoogleOAuthError.missingRefreshToken
        }

        let task = Task {
            let tokens = try await oauth.refresh(using: refreshToken)
            guard let latest = try store.load(),
                  latest.identity.subject == credentials.identity.subject,
                  latest.tokens.refreshToken == credentials.tokens.refreshToken else {
                throw GoogleCredentialError.credentialsChanged
            }
            let persistedTokens = GoogleOAuthTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken ?? refreshToken,
                expiresAt: tokens.expiresAt
            )
            try store.save(GoogleCredentials(identity: latest.identity, tokens: persistedTokens))
            return tokens.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}
