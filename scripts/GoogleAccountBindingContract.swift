import Foundation

private final class MemoryCredentials: GoogleCredentialStorage {
    var value: GoogleCredentials?

    func load() throws -> GoogleCredentials? { value }
    func save(_ credentials: GoogleCredentials) throws { value = credentials }
    func delete() throws { value = nil }
}

private struct FixedRefresh: GoogleOAuthTokenRefreshing {
    func refresh(using refreshToken: String) async throws -> GoogleOAuthTokens {
        GoogleOAuthTokens(
            accessToken: "refreshed-\(refreshToken)",
            refreshToken: nil,
            expiresAt: .now.addingTimeInterval(3600)
        )
    }
}

private enum CheckFailure: Error {
    case expectation(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.expectation(message) }
}

@main
private enum GoogleAccountBindingContract {
    static func main() async throws {
        let store = MemoryCredentials()
        let manager = GoogleCredentialManager(store: store, oauth: FixedRefresh())
        let accountA = GoogleAccountIdentity(subject: "account-A", email: nil)
        let accountB = GoogleAccountIdentity(subject: "account-B", email: nil)
        let current = GoogleOAuthTokens(
            accessToken: "token-A", refreshToken: "refresh-A",
            expiresAt: .now.addingTimeInterval(3600)
        )
        try await manager.connect(identity: accountA, tokens: current)
        let tokenA = try await manager.accessToken(for: accountA.subject)
        try require(tokenA == "token-A", "Matching account must receive its token")

        // Simulate a Settings account switch after a calendar task read account A.
        guard let observedAccount = try await manager.currentAccount() else {
            throw CheckFailure.expectation("Fixture account disappeared")
        }
        try require(observedAccount.subject == accountA.subject, "Fixture account changed")
        try await manager.connect(
            identity: accountB,
            tokens: GoogleOAuthTokens(
                accessToken: "token-B", refreshToken: "refresh-B",
                expiresAt: .now.addingTimeInterval(3600)
            )
        )
        do {
            _ = try await manager.accessToken(for: observedAccount.subject)
            throw CheckFailure.expectation("Old account accepted the new account's token")
        } catch GoogleCredentialError.credentialsChanged {
            // The caller must stop before using a token for the wrong account.
        }
        let tokenB = try await manager.accessToken(for: accountB.subject)
        try require(tokenB == "token-B", "New account must still work")

        let expiredStore = MemoryCredentials()
        let refreshManager = GoogleCredentialManager(store: expiredStore, oauth: FixedRefresh())
        try await refreshManager.connect(
            identity: accountA,
            tokens: GoogleOAuthTokens(
                accessToken: "expired-A", refreshToken: "refresh-A",
                expiresAt: .now.addingTimeInterval(-60)
            )
        )
        let refreshed = try await refreshManager.accessToken(for: accountA.subject)
        try require(refreshed == "refreshed-refresh-A",
                    "Matching refresh must return its new token")
        try require(expiredStore.value?.identity.subject == accountA.subject,
                    "Refresh changed the connected account")
        print("Google account-bound token checks passed")
    }
}
