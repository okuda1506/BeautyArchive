import Foundation
import SwiftData
import UserNotifications

@MainActor
private final class MemoryScheduler: ReminderNotificationScheduling {
    var authorized = true
    var failAdd = false
    var pending: [String: LocalNotificationPlan] = [:]
    var added = 0
    var reconciled = 0
    var removedDelivered: [String] = []
    var blockAdd = false
    var addStarted = false
    var addGate: CheckedContinuation<Void, Never>?

    func isAuthorized() async -> Bool { authorized }

    func reconcile(targets: [ReminderNotificationTarget], plans: [LocalNotificationPlan],
                   enabled: Bool, calendar: Calendar) async -> String? {
        reconciled += 1
        pending = enabled && authorized
            ? Dictionary(uniqueKeysWithValues: plans.map { ($0.identifier, $0) }) : [:]
        return nil
    }

    func add(_ plan: LocalNotificationPlan, calendar: Calendar) async throws {
        added += 1
        if failAdd { throw NSError(domain: "notification-contract", code: 1) }
        if blockAdd {
            await withCheckedContinuation { addGate = $0; addStarted = true }
        }
        pending[plan.identifier] = plan
    }

    func removeDelivered(identifier: String) { removedDelivered.append(identifier) }
}

@main
struct ReminderNotificationActionsContract {
    @MainActor
    static func main() async throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard value() else { fatalError(message) }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func date(_ day: Int, hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        let now = date(28, hour: 22)
        expect(ReminderNotificationAction.tomorrow.fireDate(now: now, calendar: calendar) == date(29, hour: 9),
               "Tomorrow must be 09:00 even when the action is selected at night")
        expect(ReminderNotificationAction.nextWeek.fireDate(now: now, calendar: calendar) == date(35, hour: 9),
               "One week must cross the month boundary correctly")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstNow = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 22))!
        let dstTomorrow = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9))!
        expect(ReminderNotificationAction.tomorrow.fireDate(now: dstNow, calendar: dstCalendar) == dstTomorrow,
               "DST snoozes must use calendar days rather than 24-hour intervals")

        let suite = "BONE.NotificationActions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ReminderPreferences.enabledKey)
        let store = ReminderNotificationSnoozeStore(defaults: defaults)
        let product = BeautyProduct(name: "Serum", category: .cosmetics)
        let unit = ProductUnit(productID: product.id, openedAt: date(1), status: .inUse,
                               usesReplacementEstimate: true, manualUsageDays: 20,
                               wantsReplacementNotification: true)
        func productTargets() -> [ReminderNotificationTarget] {
            ProductNotificationScheduler.targets(products: [product], units: [unit], calendar: calendar)
        }
        let target = productTargets()[0]
        func response(_ target: ReminderNotificationTarget, action: ReminderNotificationAction = .tomorrow)
        -> ReminderNotificationResponse {
            .init(actionIdentifier: action.rawValue, requestIdentifier: target.identifier,
                  categoryIdentifier: target.kind.rawValue, userInfo: target.userInfo)
        }
        expect(target.plan(snoozes: store, leadDays: 0, now: now, calendar: calendar) == nil,
               "An already fired normal reminder must not be repeated")
        store.set(.init(revision: target.revision, fireDate: date(29, hour: 9)), for: target.identifier)
        let reloaded = ReminderNotificationSnoozeStore(defaults: UserDefaults(suiteName: suite)!)
        expect(reloaded.record(for: target.identifier)?.fireDate == date(29, hour: 9),
               "The snooze must survive store recreation")
        expect(target.plan(snoozes: reloaded, leadDays: 7, now: now, calendar: calendar)?.fireDate == date(29, hour: 9),
               "A snooze must survive foreground reconciliation without applying lead days")
        expect(target.plan(snoozes: reloaded, leadDays: 0, now: date(30), calendar: calendar) == nil,
               "An expired snooze must not fire again")
        expect(target.matches(response(target)), "Current metadata must identify the intended target")
        var staleInfo = target.userInfo
        staleInfo["reminderRevision"] = "old-estimate"
        let stale = ReminderNotificationResponse(actionIdentifier: ReminderNotificationAction.tomorrow.rawValue,
                                                requestIdentifier: target.identifier,
                                                categoryIdentifier: target.kind.rawValue, userInfo: staleInfo)
        expect(!target.matches(stale), "A stale estimate must reject notification actions")
        expect(!target.matches(.init(actionIdentifier: ReminderNotificationAction.tomorrow.rawValue,
                                    requestIdentifier: target.identifier, categoryIdentifier: "other", userInfo: target.userInfo)),
               "Wrong categories must not be handled")
        let plan = target.plan(fireDate: date(29, hour: 9))
        let request = LocalNotificationReconciler.request(for: plan, calendar: calendar)
        expect(request.content.categoryIdentifier == target.kind.rawValue, "Scheduled notifications need an action category")
        expect(LocalNotificationReconciler.matches(request, plan, calendar: calendar), "Matching requests must be retained")
        let oldContent = UNMutableNotificationContent()
        oldContent.title = plan.title; oldContent.body = plan.body
        let oldRequest = UNNotificationRequest(identifier: plan.identifier, content: oldContent, trigger: request.trigger)
        expect(!LocalNotificationReconciler.matches(oldRequest, plan, calendar: calendar),
               "Existing notifications without actions must be replaced")

        unit.statusRaw = ProductUnitStatus.finished.rawValue
        expect(productTargets().isEmpty, "Finished products must not support snoozing")
        unit.statusRaw = ProductUnitStatus.stopped.rawValue
        expect(productTargets().isEmpty, "Stopped products must not support snoozing")
        unit.statusRaw = ProductUnitStatus.unopened.rawValue
        expect(productTargets().isEmpty, "Unopened products must not support snoozing")
        unit.statusRaw = ProductUnitStatus.inUse.rawValue
        unit.wantsReplacementNotification = false
        expect(productTargets().isEmpty, "Product notification opt-out must invalidate the target")
        unit.wantsReplacementNotification = true
        expect(ProductNotificationScheduler.targets(products: [], units: [unit], calendar: calendar).isEmpty,
               "Deleted products must not be scheduled")
        unit.adjustedUsageDays = 25
        expect(!productTargets()[0].matches(response(target)), "Changing an estimate must invalidate its old notification")
        store.retain(targets: productTargets(), enabled: true)
        expect(store.record(for: target.identifier) == nil, "Changed estimates must discard old snoozes")
        unit.adjustedUsageDays = 45
        let futureTarget = productTargets()[0]
        store.set(.init(revision: futureTarget.revision, fireDate: date(29, hour: 9)), for: futureTarget.identifier)
        expect(futureTarget.plan(snoozes: store, leadDays: 0, now: date(30), calendar: calendar) == nil,
               "An expired snooze must suppress the original reminder even when its due date is still in the future")
        unit.adjustedUsageDays = nil
        store.retain(targets: productTargets(), enabled: true)

        let visit = SalonVisit(date: date(1))
        let treatment = SalonTreatment(visitID: visit.id, name: "カット", cycleDays: 20)
        var appointments: [BeautyAppointment] = []
        var appointmentTreatments: [AppointmentTreatment] = []
        var adjustments: [SalonReminderAdjustment] = []
        func salonTargets() -> [ReminderNotificationTarget] {
            SalonNotificationScheduler.targets(visits: [visit], treatments: [treatment],
                appointments: appointments, appointmentTreatments: appointmentTreatments,
                reminderAdjustments: adjustments, now: now, calendar: calendar)
        }
        let salonTarget = salonTargets()[0]
        let booking = BeautyAppointment(title: "予約", startAt: date(30), endAt: date(30, hour: 1))
        appointments = [booking]
        appointmentTreatments = [AppointmentTreatment(appointmentID: booking.id, name: "カット")]
        expect(salonTargets().isEmpty, "Already booked treatments must not be snoozed")
        appointments = []; appointmentTreatments = []
        adjustments = [SalonReminderAdjustment(treatmentID: treatment.id, baseDueDate: date(21), overrideDueDate: date(30))]
        expect(!salonTargets()[0].matches(response(salonTarget)), "A salon due-date change must invalidate old actions")
        adjustments = []

        let scheduler = MemoryScheduler()
        var liveTargets = [target, salonTarget]
        let coordinator = ReminderNotificationCoordinator(defaults: defaults, snoozes: store,
                                                          scheduler: scheduler, targetsProvider: { liveTargets })
        await coordinator.handle(response(target), now: now, calendar: calendar)
        expect(scheduler.pending[target.identifier]?.fireDate == date(29, hour: 9), "Tomorrow action must schedule the product")
        expect(scheduler.removedDelivered == [target.identifier], "Successful actions must remove the old delivered notification")
        _ = await coordinator.reconcile(now: now, calendar: calendar)
        expect(scheduler.pending[target.identifier]?.fireDate == date(29, hour: 9), "Opening the app must preserve the snooze")
        await coordinator.handle(response(target, action: .nextWeek), now: now, calendar: calendar)
        expect(scheduler.pending[target.identifier]?.fireDate == date(35, hour: 9), "Repeated snoozes must replace the same request")
        expect(scheduler.pending.count == 1, "Snoozing repeatedly must not duplicate pending requests")
        await coordinator.handle(response(salonTarget), now: now, calendar: calendar)
        expect(scheduler.pending[salonTarget.identifier]?.fireDate == date(29, hour: 9), "Salon reminders also need tomorrow actions")
        let beforeFailure = store.record(for: target.identifier)
        scheduler.failAdd = true
        await coordinator.handle(response(target), now: now, calendar: calendar)
        expect(store.record(for: target.identifier) == beforeFailure, "Scheduling failure must restore the earlier snooze")
        expect(coordinator.takeActionError() != nil, "Background failures must be available to the foreground UI")
        expect(coordinator.takeActionError() == nil, "Action errors should be consumed once after presentation")
        scheduler.failAdd = false
        let addedBeforeInvalid = scheduler.added
        await coordinator.handle(.init(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                       requestIdentifier: target.identifier,
                                       categoryIdentifier: target.kind.rawValue, userInfo: target.userInfo),
                                 now: now, calendar: calendar)
        expect(scheduler.added == addedBeforeInvalid, "Simply opening a notification must not snooze it")
        await coordinator.handle(stale, now: now, calendar: calendar)
        expect(scheduler.added == addedBeforeInvalid, "Stale notifications must never schedule another reminder")
        liveTargets = []
        await coordinator.handle(response(target), now: now, calendar: calendar)
        expect(scheduler.added == addedBeforeInvalid && scheduler.pending.isEmpty,
               "Deleted targets must be rejected and their pending snoozes cleared")
        expect(store.record(for: target.identifier) == nil, "Deleted targets must discard their persisted snoozes")
        liveTargets = [target]
        scheduler.authorized = false
        await coordinator.handle(response(target), now: now, calendar: calendar)
        expect(scheduler.added == addedBeforeInvalid, "Denied permission must prevent rescheduling")
        scheduler.authorized = true
        defaults.set(false, forKey: ReminderPreferences.enabledKey)
        await coordinator.handle(response(target), now: now, calendar: calendar)
        expect(scheduler.added == addedBeforeInvalid, "Global notification opt-out must prevent rescheduling")
        defaults.set(true, forKey: ReminderPreferences.enabledKey)

        scheduler.blockAdd = true
        let background = Task { await coordinator.handle(response(target), now: now, calendar: calendar) }
        while !scheduler.addStarted { await Task.yield() }
        let foreground = Task { await coordinator.reconcile(now: now, calendar: calendar) }
        await Task.yield()
        scheduler.addGate?.resume()
        await background.value
        _ = await foreground.value
        expect(scheduler.pending[target.identifier]?.fireDate == date(29, hour: 9),
               "An overlapping foreground reconciliation must not overwrite the background action")
        scheduler.blockAdd = false
        store.set(.init(revision: target.revision, fireDate: date(29, hour: 9)), for: target.identifier)
        store.retain(targets: liveTargets, enabled: false)
        expect(store.record(for: target.identifier) == nil, "Disabling notifications must clear snoozes")
        expect(unit.openedAt == date(1) && unit.manualUsageDays == 20 && visit.date == date(1),
               "Notification snoozes must leave usage history and salon timing unchanged")

        let schema = Schema([BeautyProduct.self, ProductUnit.self, SalonVisit.self, SalonTreatment.self,
                             BeautyAppointment.self, AppointmentTreatment.self, SalonReminderAdjustment.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(product); context.insert(unit)
        try context.save()
        let savedName = product.name
        product.name = "Unsaved edit"
        let storageScheduler = MemoryScheduler()
        let storageCoordinator = ReminderNotificationCoordinator(defaults: defaults, scheduler: storageScheduler)
        storageCoordinator.configure(container: container)
        await storageCoordinator.handle(response(target), now: now, calendar: calendar)
        expect(storageScheduler.pending[target.identifier]?.body.contains(savedName) == true,
               "Background actions must load saved records from the shared container")
        expect(product.name == "Unsaved edit", "Background notification work must not commit or discard an open edit")
        context.rollback()
        print("Reminder notification action contract passed (\(checks) checks)")
    }
}
