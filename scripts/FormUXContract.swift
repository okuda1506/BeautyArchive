import Foundation

@main
struct FormUXContract {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let selected = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 16, minute: 35))!
        let start = AppointmentFormTiming.initialStart(selectedDay: selected, now: now, calendar: calendar)
        expect(calendar.isDate(start, inSameDayAs: selected), "Salon appointment must use the selected calendar day")
        expect(calendar.component(.hour, from: start) == 10, "New selected-day appointment starts at 10:00")
        expect(calendar.component(.minute, from: start) == 0, "Selected-day appointment uses a predictable time")
        let defaultStart = AppointmentFormTiming.initialStart(selectedDay: nil, now: now, calendar: calendar)
        expect(calendar.dateComponents([.day], from: now, to: defaultStart).day == 1, "Other entry points retain tomorrow's default")
        expect(calendar.component(.hour, from: defaultStart) == 16, "Other entry points retain the default time")

        let end = start.addingTimeInterval(90 * 60)
        let offsets: [TimeInterval] = [-3600, 7200, 86400 * 3]
        for offset in offsets {
            let movedStart = start.addingTimeInterval(offset)
            let movedEnd = AppointmentFormTiming.endAfterMovingStart(from: start, to: movedStart, end: end)
            expect(movedEnd.timeIntervalSince(movedStart) == 90 * 60, "Moving earlier/later or to another day preserves 90-minute duration")
        }
        let revisedEnd = start.addingTimeInterval(150 * 60)
        let moved = start.addingTimeInterval(7200)
        expect(AppointmentFormTiming.endAfterMovingStart(from: start, to: moved, end: revisedEnd).timeIntervalSince(moved) == 150 * 60,
               "An explicitly edited duration is preserved by the next start change")
        expect(AppointmentFormTiming.endAfterMovingStart(from: start, to: moved, end: start).timeIntervalSince(moved) == 3600,
               "Invalid zero duration falls back to one hour")
        expect(AppointmentFormTiming.endAfterMovingStart(from: start, to: moved, end: start.addingTimeInterval(-1)) > moved,
               "Invalid negative duration never creates an inverted appointment")

        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstDay = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dstStart = AppointmentFormTiming.initialStart(selectedDay: dstDay, now: now, calendar: dstCalendar)
        expect(dstCalendar.isDate(dstStart, inSameDayAs: dstDay) && dstCalendar.component(.hour, from: dstStart) == 10,
               "Selected date/time is calendar-based across daylight saving transitions")

        expect(JapanesePresentation.calendar.veryShortStandaloneWeekdaySymbols.contains("日"), "Weekdays are Japanese")
        let month = start.formatted(.dateTime.month(.wide).locale(JapanesePresentation.locale))
        expect(month.contains("月") && !month.contains("December"), "Month heading does not depend on English system language")
        let fullDate = start.japaneseFormatted(date: .complete, time: .omitted)
        expect(fullDate.contains("年") && fullDate.contains("月") && fullDate.contains("日"), "Complete dates use Japanese display")
        let dayTime = start.japaneseFormatted(date: .abbreviated, time: .shortened)
        expect(!dayTime.contains("Dec") && !dayTime.contains("AM"), "Date/time summaries do not use English month or AM labels")
        expect(start == calendar.date(bySettingHour: 10, minute: 0, second: 0, of: selected), "Display formatting never modifies stored dates")

        let snapshot = FormDraftSnapshot(text: ["商品", "メモ"], dates: [start], flags: [false], ids: [UUID()], numbers: [30], images: [Data([1, 2])])
        var state = FormDraftState()
        expect(!state.hasChanges(comparedTo: snapshot), "Before appearance there is no discard prompt")
        state.captureBaseline(snapshot)
        expect(!state.hasChanges(comparedTo: snapshot), "Opening an existing prefilled record is clean")
        var changed = snapshot
        changed.text[1] = "編集済み"
        expect(state.hasChanges(comparedTo: changed), "Typing requires discard confirmation")
        state.captureBaseline(changed)
        expect(state.hasChanges(comparedTo: changed), "Returning from a nested photo sheet must not reset the baseline")
        expect(!state.hasChanges(comparedTo: snapshot), "Reverting all input removes discard confirmation")
        changed = snapshot; changed.dates[0] = moved
        expect(state.hasChanges(comparedTo: changed), "Date edits are protected")
        changed = snapshot; changed.flags[0] = true
        expect(state.hasChanges(comparedTo: changed), "Toggle edits are protected")
        changed = snapshot; changed.ids.append(UUID())
        expect(state.hasChanges(comparedTo: changed), "Adding/removing a draft photo or treatment is protected")
        changed = snapshot; changed.numbers[0] = 45
        expect(state.hasChanges(comparedTo: changed), "Treatment cycle edits are protected")
        changed = snapshot; changed.images[0] = Data([3, 4])
        expect(state.hasChanges(comparedTo: changed), "A replacement/cropped image is protected")

        let visible = ["name", "price", "note"]
        expect(FormInputNavigation.next(after: "name", in: visible) == "price", "Next advances to the visible numeric field")
        expect(FormInputNavigation.next(after: "price", in: visible) == "note", "Numeric keyboard Next advances")
        expect(FormInputNavigation.next(after: "note", in: visible) == nil, "Done at the last field dismisses keyboard")
        expect(FormInputNavigation.next(after: "hidden", in: visible) == nil, "A removed field cannot send focus to a hidden input")
        expect(FormInputNavigation.next(after: nil, in: visible) == nil, "No focus remains no focus")
        expect(FormInputNavigation.next(after: "name", in: ["name", "note"]) == "note", "Collapsed optional fields are skipped")
        print("Form UX: \(checks) checks passed")
    }
}
