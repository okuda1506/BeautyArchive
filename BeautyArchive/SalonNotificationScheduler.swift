import Foundation

@MainActor
enum SalonNotificationScheduler {
    private static let identifierPrefix = "beautyarchive.salon-booking."

    static func reconcile(
        visits: [SalonVisit],
        treatments: [SalonTreatment],
        appointments: [BeautyAppointment],
        appointmentTreatments: [AppointmentTreatment],
        enabled: Bool,
        leadDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> String? {
        let actions = SalonMaintenance.actions(
            visits: visits,
            treatments: treatments,
            appointments: appointments,
            appointmentTreatments: appointmentTreatments,
            referenceDate: now,
            calendar: calendar
        )
        let plans = actions.compactMap { action -> LocalNotificationPlan? in
            guard action.kind == .salonNeedsBooking,
                  let fireDate = LocalNotificationReconciler.fireDate(
                    for: action.date, leadDays: leadDays, now: now, calendar: calendar
                  )
            else { return nil }
            return LocalNotificationPlan(
                identifier: identifierPrefix + action.id.uuidString,
                fireDate: fireDate,
                title: "次の施術の予約時期です",
                body: "\(action.title)の次回目安が近づいています。",
                userInfo: ["treatmentID": action.id.uuidString]
            )
        }.sorted { $0.fireDate < $1.fireDate }
        return await LocalNotificationReconciler.reconcile(
            prefix: identifierPrefix, plans: plans, enabled: enabled, calendar: calendar
        )
    }
}
