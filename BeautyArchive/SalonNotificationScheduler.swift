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

/// Registered plans always notify on the preceding calendar day; maintenance lead time does not apply.
@MainActor
enum AppointmentNotificationScheduler {
    static func targets(
        appointments: [BeautyAppointment], purchasePlans: [ProductPurchasePlan],
        now: Date = .now, calendar: Calendar = .current
    ) -> [ReminderNotificationTarget] {
        let time = DateFormatter()
        time.locale = Locale(identifier: "ja_JP")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "H:mm"
        let salon = appointments.compactMap { appointment -> ReminderNotificationTarget? in
            guard !appointment.isCancelled, !appointment.isCompleted, appointment.startAt > now,
                  let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: appointment.startAt))
            else { return nil }
            return ReminderNotificationTarget(
                kind: .salonAppointment, id: appointment.id,
                revision: "\(appointment.startAt.timeIntervalSince1970):\(appointment.title)",
                reminderDate: day, usesLeadTime: false,
                title: "明日は美容院の予定です",
                body: "\(appointment.title)は明日\(time.string(from: appointment.startAt))です。",
                metadata: ["appointmentID": appointment.id.uuidString]
            )
        }
        let purchases = purchasePlans.compactMap { purchase -> ReminderNotificationTarget? in
            guard purchase.status == .planned,
                  calendar.startOfDay(for: purchase.plannedAt) > calendar.startOfDay(for: now),
                  let day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: purchase.plannedAt))
            else { return nil }
            return ReminderNotificationTarget(
                kind: .purchasePlan, id: purchase.id,
                revision: "\(purchase.plannedAt.timeIntervalSince1970):\(purchase.productName)",
                reminderDate: day, usesLeadTime: false,
                title: "明日は購入予定日です",
                body: "\(purchase.productName)の購入予定があります。",
                metadata: ["purchasePlanID": purchase.id.uuidString]
            )
        }
        return salon + purchases
    }
}
