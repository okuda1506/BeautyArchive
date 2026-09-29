import Foundation
import SwiftData
import UserNotifications

extension Notification.Name {
    static let reminderNotificationActionFinished = Notification.Name("reminderNotificationActionFinished")
}

@MainActor
protocol ReminderNotificationScheduling {
    func isAuthorized() async -> Bool
    func reconcile(targets: [ReminderNotificationTarget], plans: [LocalNotificationPlan],
                   enabled: Bool, calendar: Calendar) async -> String?
    func add(_ plan: LocalNotificationPlan, calendar: Calendar) async throws
    func removeDelivered(identifier: String)
}

@MainActor
struct SystemReminderNotificationScheduling: ReminderNotificationScheduling {
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    func reconcile(targets: [ReminderNotificationTarget], plans: [LocalNotificationPlan],
                   enabled: Bool, calendar: Calendar) async -> String? {
        await LocalNotificationReconciler.reconcile(
            targets: targets, plans: plans, enabled: enabled, calendar: calendar
        )
    }

    func add(_ plan: LocalNotificationPlan, calendar: Calendar) async throws {
        try await UNUserNotificationCenter.current().add(
            LocalNotificationReconciler.request(for: plan, calendar: calendar)
        )
    }

    func removeDelivered(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

/// Serializes foreground reconciliation and background notification actions so that
/// opening the app cannot overwrite a snooze with an older notification plan.
@MainActor
final class ReminderNotificationCoordinator {
    static let shared = ReminderNotificationCoordinator()
    private static let actionErrorKey = "reminders.notificationActionError"
    private let defaults: UserDefaults
    private let snoozes: ReminderNotificationSnoozeStore
    private let scheduler: any ReminderNotificationScheduling
    private let targetsProvider: (() throws -> [ReminderNotificationTarget])?
    private var container: ModelContainer?
    private var queuedTask: Task<String?, Never>?
    private var queueGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        snoozes: ReminderNotificationSnoozeStore? = nil,
        scheduler: (any ReminderNotificationScheduling)? = nil,
        targetsProvider: (() throws -> [ReminderNotificationTarget])? = nil
    ) {
        self.defaults = defaults
        self.snoozes = snoozes ?? ReminderNotificationSnoozeStore(defaults: defaults)
        self.scheduler = scheduler ?? SystemReminderNotificationScheduling()
        self.targetsProvider = targetsProvider
    }

    func configure(container: ModelContainer) {
        self.container = container
    }

    func reconcile(now: Date = .now, calendar: Calendar = .current) async -> String? {
        await enqueue {
            await self.performReconciliation(now: now, calendar: calendar)
        }
    }

    func takeActionError(isForeground: Bool) -> String? {
        guard isForeground else { return nil }
        let error = defaults.string(forKey: Self.actionErrorKey)
        defaults.removeObject(forKey: Self.actionErrorKey)
        return error
    }

    func handle(_ response: ReminderNotificationResponse,
                now: Date = .now, calendar: Calendar = .current) async {
        guard let action = ReminderNotificationAction(rawValue: response.actionIdentifier) else { return }
        _ = await enqueue {
            do {
                try await self.snooze(response, action: action, now: now, calendar: calendar)
            } catch {
                // A background action has no presenting view. Surface failures on the
                // next foreground reconciliation instead of silently losing the error.
                self.defaults.set(error.localizedDescription, forKey: Self.actionErrorKey)
            }
            NotificationCenter.default.post(name: .reminderNotificationActionFinished, object: nil)
            return nil
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> String?) async -> String? {
        let previous = queuedTask
        queueGeneration += 1
        let generation = queueGeneration
        let task = Task {
            _ = await previous?.value
            return await operation()
        }
        queuedTask = task
        let result = await task.value
        if queueGeneration == generation { queuedTask = nil }
        return result
    }

    private func loadTargets(now: Date, calendar: Calendar) throws -> [ReminderNotificationTarget] {
        if let targetsProvider { return try targetsProvider() }
        guard let container else { throw ActionError.storageUnavailable }
        // Use the same persistent container as SwiftUI, with a fresh context so the
        // background action sees saved records without committing an open edit form.
        let context = ModelContext(container)
        return try ProductNotificationScheduler.targets(
            products: context.fetch(FetchDescriptor<BeautyProduct>()),
            units: context.fetch(FetchDescriptor<ProductUnit>()), calendar: calendar
        ) + SalonNotificationScheduler.targets(
            visits: context.fetch(FetchDescriptor<SalonVisit>()),
            treatments: context.fetch(FetchDescriptor<SalonTreatment>()),
            appointments: context.fetch(FetchDescriptor<BeautyAppointment>()),
            appointmentTreatments: context.fetch(FetchDescriptor<AppointmentTreatment>()),
            reminderAdjustments: context.fetch(FetchDescriptor<SalonReminderAdjustment>()),
            now: now, calendar: calendar
        )
    }

    private func performReconciliation(now: Date, calendar: Calendar) async -> String? {
        do {
            let targets = try loadTargets(now: now, calendar: calendar)
            let enabled = defaults.bool(forKey: ReminderPreferences.enabledKey)
            snoozes.retain(targets: targets, enabled: enabled)
            let leadDays = ReminderPreferences.effectiveLeadDays(
                choice: defaults.integer(forKey: ReminderPreferences.leadChoiceKey),
                customDays: defaults.integer(forKey: ReminderPreferences.customLeadDaysKey)
            )
            let notificationTimeMinutes = ReminderPreferences.notificationTimeMinutes(defaults: defaults)
            let plans = targets.compactMap {
                $0.plan(
                    snoozes: snoozes, leadDays: leadDays, now: now, calendar: calendar,
                    notificationTimeMinutes: notificationTimeMinutes
                )
            }.sorted { $0.fireDate < $1.fireDate }
            return await scheduler.reconcile(targets: targets, plans: plans,
                                             enabled: enabled, calendar: calendar)
        } catch {
            return error.localizedDescription
        }
    }

    private func snooze(_ response: ReminderNotificationResponse,
                        action: ReminderNotificationAction, now: Date, calendar: Calendar) async throws {
        let targets = try loadTargets(now: now, calendar: calendar)
        guard defaults.bool(forKey: ReminderPreferences.enabledKey),
              let target = targets.first(where: { $0.matches(response) }),
              await scheduler.isAuthorized()
        else {
            if let error = await performReconciliation(now: now, calendar: calendar) {
                throw ActionError.schedulingFailed(error)
            }
            return
        }
        let notificationTimeMinutes = ReminderPreferences.notificationTimeMinutes(defaults: defaults)
        guard let date = action.fireDate(
            now: now, calendar: calendar, notificationTimeMinutes: notificationTimeMinutes
        ), date > now
        else { throw ActionError.invalidDate }
        let previous = snoozes.record(for: target.identifier)
        snoozes.set(.init(revision: target.revision, fireDate: date), for: target.identifier)
        do {
            try await scheduler.add(target.plan(fireDate: date), calendar: calendar)
        } catch {
            snoozes.set(previous, for: target.identifier)
            throw error
        }
        scheduler.removeDelivered(identifier: target.identifier)
    }

    private enum ActionError: LocalizedError {
        case storageUnavailable
        case invalidDate
        case schedulingFailed(String)

        var errorDescription: String? {
            switch self {
            case .storageUnavailable: "通知の対象となる記録を読み込めませんでした。"
            case .invalidDate: "再通知する日時を計算できませんでした。"
            case .schedulingFailed(let message): message
            }
        }
    }
}
