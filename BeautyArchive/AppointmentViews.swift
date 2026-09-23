import SwiftData
import SwiftUI

struct AppointmentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BeautyAppointment.startAt) private var appointments: [BeautyAppointment]
    @Query private var treatments: [AppointmentTreatment]
    @State private var selectedDate = Date.now
    @State private var showingAdd = false
    @State private var errorMessage: String?

    private var selectedAppointments: [BeautyAppointment] {
        appointments.filter { Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            List {
                MonthCalendarView(selectedDate: $selectedDate, appointments: appointments)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))

                Section(selectedDate.formatted(date: .complete, time: .omitted)) {
                    if selectedAppointments.isEmpty {
                        Text(appointments.isEmpty
                            ? "美容予定はまだありません。右上の＋から追加できます。"
                            : "この日の予定はありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedAppointments) { appointment in
                            NavigationLink {
                                AppointmentDetail(appointment: appointment) { selectedDate = $0 }
                            } label: {
                                appointmentRow(appointment)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("予定")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("美容予定を追加", systemImage: "plus") { showingAdd = true }
                        .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AppointmentForm { selectedDate = $0 }
            }
            .alert("削除できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func appointmentRow(_ appointment: BeautyAppointment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(appointment.title).font(.headline)
                Spacer()
                if appointment.isCancelled {
                    Text("キャンセル済み")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appointment.isCompleted {
                    Text("記録済み")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(appointment.startAt, format: .dateTime.hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            let names = treatments.filter { $0.appointmentID == appointment.id }
                .map(\.name).joined(separator: "・")
            if !names.isEmpty {
                Text(names)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let appointment = selectedAppointments[index]
            for treatment in treatments where treatment.appointmentID == appointment.id {
                modelContext.delete(treatment)
            }
            modelContext.delete(appointment)
        }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let appointments: [BeautyAppointment]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        return calendar.date(from: components) ?? calendar.startOfDay(for: selectedDate)
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date?] {
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        return Array(repeating: nil, count: leading)
            + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: monthStart) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("前の月", systemImage: "chevron.left") { changeMonth(by: -1) }
                    .labelStyle(.iconOnly)
                Spacer()
                Text(monthStart, format: .dateTime.year().month())
                    .font(.headline)
                Spacer()
                Button("次の月", systemImage: "chevron.right") { changeMonth(by: 1) }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { item in
                    if let date = item.element {
                        dayButton(for: date)
                    } else {
                        Color.clear.frame(minHeight: 48)
                    }
                }
            }
        }
    }

    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasAppointment = appointments.contains { calendar.isDate($0.startAt, inSameDayAs: date) }
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text(date, format: .dateTime.day())
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Color.primary : Color.clear, in: Circle())
                Circle()
                    .fill(hasAppointment ? (isSelected ? Color.primary : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))\(hasAppointment ? "、予定あり" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func changeMonth(by offset: Int) {
        selectedDate = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? selectedDate
    }
}

private struct AppointmentDetail: View {
    let appointment: BeautyAppointment
    let onSave: (Date) -> Void
    @Query private var allTreatments: [AppointmentTreatment]
    @State private var showingEdit = false

    private var treatments: [AppointmentTreatment] {
        allTreatments.filter { $0.appointmentID == appointment.id }
    }

    var body: some View {
        List {
            Section("予約") {
                LabeledContent("状態", value: appointment.isCancelled
                    ? "キャンセル済み" : appointment.isCompleted ? "記録済み" : "予約済み")
                LabeledContent("開始", value: appointment.startAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("終了", value: appointment.endAt.formatted(date: .abbreviated, time: .shortened))
                if !appointment.shopName.isEmpty {
                    LabeledContent("店舗", value: appointment.shopName)
                }
                if !appointment.isCancelled && !appointment.isCompleted && appointment.startAt < .now {
                    Text("予定日時を過ぎています。施術記録を追加するまで、来店済みにはなりません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section("対象の施術") {
                ForEach(treatments) { treatment in Text(treatment.name) }
            }
            if !appointment.note.isEmpty {
                Section("メモ") { Text(appointment.note) }
            }
        }
        .navigationTitle(appointment.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AppointmentForm(appointment: appointment, treatments: treatments, onSave: onSave)
        }
    }
}

private struct AppointmentTreatmentDraft: Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String = "") {
        self.id = id
        self.name = name
    }
}

struct AppointmentForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let appointment: BeautyAppointment?
    let existingTreatments: [AppointmentTreatment]
    let onSave: (Date) -> Void
    @State private var title: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var shopName: String
    @State private var note: String
    @State private var statusRaw: String
    @State private var drafts: [AppointmentTreatmentDraft]
    @State private var errorMessage: String?

    init(
        appointment: BeautyAppointment? = nil,
        treatments: [AppointmentTreatment] = [],
        onSave: @escaping (Date) -> Void = { _ in }
    ) {
        self.appointment = appointment
        self.existingTreatments = treatments
        self.onSave = onSave
        let defaultStart = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        _title = State(initialValue: appointment?.title ?? "")
        _startAt = State(initialValue: appointment?.startAt ?? defaultStart)
        _endAt = State(initialValue: appointment?.endAt ?? defaultStart.addingTimeInterval(3600))
        _shopName = State(initialValue: appointment?.shopName ?? "")
        _note = State(initialValue: appointment?.note ?? "")
        _statusRaw = State(initialValue: appointment?.statusRaw ?? "booked")
        _drafts = State(initialValue: treatments.isEmpty
            ? [AppointmentTreatmentDraft()]
            : treatments.map { AppointmentTreatmentDraft(id: $0.id, name: $0.name) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("予定") {
                    TextField("予定名（例：美容院）", text: $title)
                    DatePicker("開始", selection: $startAt)
                    DatePicker("終了", selection: $endAt)
                    if endAt <= startAt {
                        Text("終了は開始より後にしてください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("店舗（任意）", text: $shopName)
                    Picker("状態", selection: $statusRaw) {
                        Text("予約済み").tag("booked")
                        Text("キャンセル済み").tag("cancelled")
                    }
                    if statusRaw == "cancelled" {
                        Text("外部の予約サービスで行った予約は、ここではキャンセルされません。予約先でも手続きしてください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("対象の施術") {
                    ForEach($drafts) { $draft in
                        HStack {
                            TextField("施術名（例：カット）", text: $draft.name)
                            if drafts.count > 1 {
                                Button("施術を削除", systemImage: "minus.circle") {
                                    drafts.removeAll { $0.id == draft.id }
                                }
                                .labelStyle(.iconOnly)
                                .tint(.red)
                            }
                        }
                    }
                    Button("施術を追加", systemImage: "plus") {
                        drafts.append(AppointmentTreatmentDraft())
                    }
                    if hasDuplicateNames {
                        Text("同じ施術名は1件にまとめてください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("メモ（任意）") {
                    TextField("予約時のメモ", text: $note, axis: .vertical)
                }
            }
            .onChange(of: startAt) { _, newStart in
                if endAt <= newStart { endAt = newStart.addingTimeInterval(3600) }
            }
            .navigationTitle(appointment == nil ? "美容予定を追加" : "美容予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!isValid)
                }
            }
            .alert("保存できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var hasDuplicateNames: Bool {
        let names = drafts.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        }.filter { !$0.isEmpty }
        return Set(names).count != names.count
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endAt > startAt
            && !drafts.isEmpty
            && drafts.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !hasDuplicateNames
    }

    private func save() {
        guard isValid else { return }
        let target = appointment ?? BeautyAppointment(title: title, startAt: startAt, endAt: endAt)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.startAt = startAt
        target.endAt = endAt
        target.shopName = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.statusRaw = statusRaw
        target.updatedAt = .now
        if appointment == nil { modelContext.insert(target) }

        let draftIDs = Set(drafts.map(\.id))
        for treatment in existingTreatments where !draftIDs.contains(treatment.id) {
            modelContext.delete(treatment)
        }
        let existingByID = Dictionary(uniqueKeysWithValues: existingTreatments.map { ($0.id, $0) })
        for draft in drafts {
            let treatment = existingByID[draft.id] ?? AppointmentTreatment(
                id: draft.id, appointmentID: target.id, name: draft.name
            )
            treatment.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingByID[draft.id] == nil { modelContext.insert(treatment) }
        }
        do {
            try modelContext.save()
            onSave(target.startAt)
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
