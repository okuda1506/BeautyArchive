import Foundation

/// Localized display only. API timestamps and export formats keep their own formatters.
enum JapanesePresentation {
    static let locale = Locale(identifier: "ja_JP")

    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }
}

extension Date {
    func japaneseFormatted(
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle
    ) -> String {
        formatted(Date.FormatStyle(
            date: date, time: time, locale: JapanesePresentation.locale,
            calendar: .current, timeZone: .current
        ))
    }
}

enum AppointmentFormTiming {
    static func initialStart(selectedDay: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        guard let selectedDay else {
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        }
        // The calendar selection supplies the day; start new appointments at 10:00.
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDay)
            ?? calendar.startOfDay(for: selectedDay)
    }

    static func endAfterMovingStart(from oldStart: Date, to newStart: Date, end: Date) -> Date {
        let duration = end.timeIntervalSince(oldStart)
        return newStart.addingTimeInterval(duration > 0 ? duration : 3600)
    }
}
