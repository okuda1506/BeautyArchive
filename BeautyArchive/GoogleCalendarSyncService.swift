import Foundation
import SwiftData

extension Notification.Name {
    static let googleCalendarSyncChanged = Notification.Name("BONEGoogleCalendarSyncChanged")
    static let googleCalendarSyncPersistenceFailed = Notification.Name(
        "BONEGoogleCalendarSyncPersistenceFailed"
    )
}

@MainActor
final class GoogleCalendarSyncService {
    static let shared = GoogleCalendarSyncService()

    private let connection = GoogleCalendarConnection.shared
    private let writer = GoogleCalendarWriter()
    private var isRunning = false
    private var needsAnotherPass = false

    private init() {}

    /// Returns a local persistence error. Per-event Google errors are saved on their links.
    func syncPending(in context: ModelContext) async -> String? {
        if isRunning {
            needsAnotherPass = true
            return nil
        }
        isRunning = true
        defer { isRunning = false }
        do {
            var didChange = false
            repeat {
                needsAnotherPass = false
                didChange = try await syncPass(in: context) || didChange
            } while needsAnotherPass
            if didChange {
                NotificationCenter.default.post(name: .googleCalendarSyncChanged, object: nil)
            }
            return nil
        } catch {
            let message = error.localizedDescription
            NotificationCenter.default.post(
                name: .googleCalendarSyncPersistenceFailed, object: message
            )
            return message
        }
    }

    private func syncPass(in context: ModelContext) async throws -> Bool {
        let links = try context.fetch(FetchDescriptor<GoogleAppointmentLink>())
            .filter { $0.state.needsSync }
        guard !links.isEmpty else { return false }
        let account: GoogleAccountIdentity
        do {
            guard let connected = try await connection.currentAccount() else { return false }
            account = connected
        } catch {
            for link in links {
                link.stateRaw = link.state.isDeletion
                    ? GoogleAppointmentSyncState.failedDelete.rawValue
                    : GoogleAppointmentSyncState.failedUpsert.rawValue
                link.lastError = error.localizedDescription
            }
            try context.save()
            return true
        }

        let appointments = Dictionary(
            try context.fetch(FetchDescriptor<BeautyAppointment>()).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var didChange = false
        for link in links where link.accountSubject == account.subject {
            if Task.isCancelled { return didChange }
            guard link.eventID == GoogleCalendarEventIdentity.eventID(for: link.appointmentID),
                  link.calendarID == "primary" else {
                link.stateRaw = link.state.isDeletion
                    ? GoogleAppointmentSyncState.failedDelete.rawValue
                    : GoogleAppointmentSyncState.failedUpsert.rawValue
                link.lastError = "Google連携情報を確認できません。"
                try context.save()
                didChange = true
                continue
            }
            if !link.state.isDeletion && (appointments[link.appointmentID] == nil
                || appointments[link.appointmentID]?.isCancelled == true) {
                link.markForDeletion()
                try context.save()
            }
            let deleting = link.state.isDeletion
            let revision = link.revision
            do {
                let token = try await connection.accessToken(for: link.accountSubject)
                if deleting {
                    do {
                        try await writer.delete(
                            link.calendarAppointment,
                            calendarID: link.calendarID, accessToken: token
                        )
                    } catch GoogleCalendarWriteError.notFound {
                        // Already removed on Google; the requested end state is satisfied.
                    }
                } else {
                    _ = try await writer.create(
                        link.calendarAppointment,
                        calendarID: link.calendarID, accessToken: token
                    )
                }
                if link.revision != revision {
                    needsAnotherPass = true
                    continue
                }
                if deleting {
                    context.delete(link)
                } else {
                    link.stateRaw = GoogleAppointmentSyncState.synced.rawValue
                    link.lastError = nil
                    link.updatedAt = .now
                }
                try context.save()
                didChange = true
            } catch {
                if Task.isCancelled { return didChange }
                if link.revision != revision {
                    needsAnotherPass = true
                    continue
                }
                link.stateRaw = deleting
                    ? GoogleAppointmentSyncState.failedDelete.rawValue
                    : GoogleAppointmentSyncState.failedUpsert.rawValue
                link.lastError = error.localizedDescription
                link.updatedAt = .now
                try context.save()
                didChange = true
            }
        }
        return didChange
    }
}
