import Foundation

@MainActor
enum SalonNotificationScheduler {
    static func targets(
        visits: [SalonVisit],
        treatments: [SalonTreatment],
        appointments: [BeautyAppointment],
        appointmentTreatments: [AppointmentTreatment],
        reminderAdjustments: [SalonReminderAdjustment],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ReminderNotificationTarget] {
        let actions = SalonMaintenance.actions(
            visits: visits,
            treatments: treatments,
            appointments: appointments,
            appointmentTreatments: appointmentTreatments,
            reminderAdjustments: reminderAdjustments,
            referenceDate: now,
            calendar: calendar
        )
        return actions.compactMap { action -> ReminderNotificationTarget? in
            guard action.kind == .salonNeedsBooking, let baselineDate = action.baselineDate
            else { return nil }
            return ReminderNotificationTarget(
                kind: .salon, id: action.id,
                revision: "\(action.visitID?.uuidString ?? ""):\(baselineDate.timeIntervalSince1970):\(action.date.timeIntervalSince1970):\(action.snoozedReminderDate?.timeIntervalSince1970 ?? 0)",
                reminderDate: action.snoozedReminderDate ?? action.date,
                usesLeadTime: action.snoozedReminderDate == nil,
                title: "次の施術の予約時期です",
                body: "\(action.title)の次回目安が近づいています。",
                metadata: ["treatmentID": action.id.uuidString]
            )
        }
    }
}
