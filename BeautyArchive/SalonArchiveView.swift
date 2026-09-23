import SwiftData
import SwiftUI

struct SalonArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SalonVisit.date, order: .reverse) private var visits: [SalonVisit]
    @Query private var treatments: [SalonTreatment]
    @Query private var photos: [SalonPhoto]
    @State private var showingAdd = false
    @State private var copyingFrom: SalonVisit?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView(
                        "美容院の記録はまだありません",
                        systemImage: "scissors",
                        description: Text("施術内容を追加すると、次回の目安をホームに表示します。")
                    )
                } else {
                    List {
                        ForEach(visits) { visit in
                            NavigationLink {
                                SalonVisitDetail(visit: visit)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(visit.date, format: .dateTime.year().month().day())
                                        .font(.headline)
                                    Text(treatmentNames(for: visit))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if !visit.salonName.isEmpty {
                                        Text(visit.salonName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("記録")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let latestVisit = visits.first {
                        Menu {
                            Button("新しく作成", systemImage: "square.and.pencil") {
                                copyingFrom = nil
                                showingAdd = true
                            }
                            Button("前回のサロン情報を使う", systemImage: "doc.on.doc") {
                                copyingFrom = latestVisit
                                showingAdd = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel("美容院の記録を追加")
                        }
                    } else {
                        Button("美容院の記録を追加", systemImage: "plus") {
                            copyingFrom = nil
                            showingAdd = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                SalonVisitForm(copying: copyingFrom)
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

    private func treatmentNames(for visit: SalonVisit) -> String {
        treatments.filter { $0.visitID == visit.id }.map(\.name).joined(separator: "・")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let visit = visits[index]
            for treatment in treatments where treatment.visitID == visit.id {
                modelContext.delete(treatment)
            }
            for photo in photos where photo.visitID == visit.id {
                modelContext.delete(photo)
            }
            modelContext.delete(visit)
        }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct SalonVisitDetail: View {
    let visit: SalonVisit
    @Query private var allTreatments: [SalonTreatment]
    @Query private var allPhotos: [SalonPhoto]
    @State private var showingEdit = false

    private var treatments: [SalonTreatment] {
        allTreatments.filter { $0.visitID == visit.id }
    }

    private var photos: [SalonPhoto] {
        allPhotos.filter { $0.visitID == visit.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section("施術") {
                LabeledContent("来店日", value: visit.date.formatted(date: .abbreviated, time: .omitted))
                ForEach(treatments) { treatment in
                    LabeledContent(treatment.name, value: "\(treatment.cycleDays)日周期")
                }
            }
            if !photos.isEmpty {
                Section("写真") {
                    SalonPhotoGallery(photos: photos)
                }
            }
            if !visit.salonName.isEmpty || !visit.stylistName.isEmpty || visit.price != nil {
                Section("サロン") {
                    if !visit.salonName.isEmpty { LabeledContent("店名", value: visit.salonName) }
                    if !visit.stylistName.isEmpty { LabeledContent("担当", value: visit.stylistName) }
                    if let price = visit.price { LabeledContent("金額", value: "¥\(price.formatted())") }
                }
            }
            if !visit.orderNote.isEmpty || !visit.impression.isEmpty || !visit.nextVisitNote.isEmpty {
                Section("メモ") {
                    if !visit.orderNote.isEmpty { note("オーダー", visit.orderNote) }
                    if !visit.impression.isEmpty { note("感想", visit.impression) }
                    if !visit.nextVisitNote.isEmpty { note("次回", visit.nextVisitNote) }
                }
            }
            if let components = URLComponents(string: visit.bookingURL),
               ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
               let url = components.url {
                Section {
                    Link("予約先を開く", destination: url)
                }
            }
        }
        .navigationTitle("美容院の記録")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            SalonVisitForm(visit: visit, treatments: treatments)
        }
    }

    private func note(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private struct TreatmentDraft: Identifiable {
    let id: UUID
    var name: String
    var cycleDays: Int

    init(id: UUID = UUID(), name: String = "", cycleDays: Int = 45) {
        self.id = id
        self.name = name
        self.cycleDays = cycleDays
    }
}

struct SalonVisitForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var savedVisits: [SalonVisit]
    @Query private var savedTreatments: [SalonTreatment]
    @Query private var savedPhotos: [SalonPhoto]
    let visit: SalonVisit?
    let existingTreatments: [SalonTreatment]
    @State private var date: Date
    @State private var salonName: String
    @State private var stylistName: String
    @State private var orderNote: String
    @State private var impression: String
    @State private var nextVisitNote: String
    @State private var bookingURL: String
    @State private var priceText: String
    @State private var drafts: [TreatmentDraft]
    @State private var newPhotos: [SalonPhotoDraft] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var showingDetails: Bool
    @State private var errorMessage: String?

    init(visit: SalonVisit? = nil, treatments: [SalonTreatment] = [], copying: SalonVisit? = nil) {
        self.visit = visit
        self.existingTreatments = treatments
        _date = State(initialValue: visit?.date ?? .now)
        _salonName = State(initialValue: visit?.salonName ?? copying?.salonName ?? "")
        _stylistName = State(initialValue: visit?.stylistName ?? copying?.stylistName ?? "")
        _orderNote = State(initialValue: visit?.orderNote ?? "")
        _impression = State(initialValue: visit?.impression ?? "")
        _nextVisitNote = State(initialValue: visit?.nextVisitNote ?? "")
        _bookingURL = State(initialValue: visit?.bookingURL ?? copying?.bookingURL ?? "")
        _priceText = State(initialValue: visit?.price.map(String.init) ?? "")
        _drafts = State(initialValue: treatments.isEmpty
            ? [TreatmentDraft()]
            : treatments.map { TreatmentDraft(id: $0.id, name: $0.name, cycleDays: $0.cycleDays) })
        _showingDetails = State(initialValue: visit != nil || copying != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("来店日") {
                    DatePicker("来店日", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("施術名（例：カット）", text: $draft.name)
                                    .textInputAutocapitalization(.never)
                                if drafts.count > 1 {
                                    Button("施術を削除", systemImage: "minus.circle") {
                                        drafts.removeAll { $0.id == draft.id }
                                    }
                                    .labelStyle(.iconOnly)
                                    .tint(.red)
                                }
                            }
                            if !treatmentChoices.isEmpty {
                                Menu {
                                    ForEach(treatmentChoices) { choice in
                                        Button("\(choice.name) · \(choice.cycleDays)日") {
                                            draft.name = choice.name
                                            draft.cycleDays = choice.cycleDays
                                        }
                                    }
                                } label: {
                                    Label("過去の施術から選ぶ", systemImage: "clock.arrow.circlepath")
                                        .font(.subheadline)
                                }
                            }
                            Stepper("次回目安：\(draft.cycleDays)日後", value: $draft.cycleDays, in: 1...365)
                                .font(.subheadline)
                        }
                    }
                    Button("施術を追加", systemImage: "plus") {
                        drafts.append(TreatmentDraft())
                    }
                    if hasDuplicateNames {
                        Text("同じ施術名は1件にまとめてください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("施術と次回目安")
                } footer: {
                    Text("同じ施術名の最新の来店日から、次回の目安を計算します。")
                }
                Section("写真（任意）") {
                    SalonPhotoEditor(
                        existing: existingPhotos,
                        newPhotos: $newPhotos,
                        removedPhotoIDs: $removedPhotoIDs
                    )
                }
                Section("オーダー（任意）") {
                    TextField("オーダー", text: $orderNote, axis: .vertical)
                }
                Section {
                    DisclosureGroup(isExpanded: $showingDetails) {
                        TextField("店名", text: $salonName)
                        TextField("担当者", text: $stylistName)
                        TextField("金額", text: $priceText)
                            .keyboardType(.numberPad)
                        if !priceText.isEmpty && Int(priceText).map({ $0 >= 0 }) != true {
                            Text("金額は0以上の数字で入力してください。")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        TextField("予約URL", text: $bookingURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !bookingURL.isEmpty && validBookingURL == nil {
                            Text("https:// または http:// から始まるURLを入力してください。")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        TextField("感想", text: $impression, axis: .vertical)
                        TextField("次回のメモ", text: $nextVisitNote, axis: .vertical)
                    } label: {
                        Label("サロン情報・感想などの詳細", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle(visit == nil ? "美容院の記録を追加" : "美容院の記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
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

    private var isValid: Bool {
        return !drafts.isEmpty && drafts.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } && !hasDuplicateNames
            && (priceText.isEmpty || Int(priceText).map { $0 >= 0 } == true)
            && (bookingURL.isEmpty || validBookingURL != nil)
    }

    private var hasDuplicateNames: Bool {
        let names = drafts.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        }.filter { !$0.isEmpty }
        return Set(names).count != names.count
    }

    private var treatmentChoices: [SalonTreatmentChoice] {
        SalonMaintenance.treatmentChoices(visits: savedVisits, treatments: savedTreatments)
    }

    private var existingPhotos: [SalonPhoto] {
        guard let visit else { return [] }
        return savedPhotos.filter { $0.visitID == visit.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var validBookingURL: URL? {
        let components = URLComponents(string: bookingURL)
        guard ["https", "http"].contains(components?.scheme?.lowercased() ?? ""),
              components?.host != nil else { return nil }
        return components?.url
    }

    private func save() {
        guard isValid else { return }
        let target = visit ?? SalonVisit()
        target.date = date
        target.salonName = salonName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.stylistName = stylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.orderNote = orderNote.trimmingCharacters(in: .whitespacesAndNewlines)
        target.impression = impression.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nextVisitNote = nextVisitNote.trimmingCharacters(in: .whitespacesAndNewlines)
        target.bookingURL = bookingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        target.price = Int(priceText)
        if visit == nil { modelContext.insert(target) }

        let draftIDs = Set(drafts.map(\.id))
        for treatment in existingTreatments where !draftIDs.contains(treatment.id) {
            modelContext.delete(treatment)
        }
        let existingByID = Dictionary(uniqueKeysWithValues: existingTreatments.map { ($0.id, $0) })
        for draft in drafts {
            let treatment = existingByID[draft.id] ?? SalonTreatment(
                id: draft.id, visitID: target.id, name: draft.name, cycleDays: draft.cycleDays
            )
            treatment.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            treatment.cycleDays = draft.cycleDays
            if existingByID[draft.id] == nil { modelContext.insert(treatment) }
        }
        for photo in existingPhotos where removedPhotoIDs.contains(photo.id) {
            modelContext.delete(photo)
        }
        let nextSortOrder = (existingPhotos.map(\.sortOrder).max() ?? -1) + 1
        for (index, draft) in newPhotos.enumerated() {
            modelContext.insert(SalonPhoto(
                visitID: target.id,
                sortOrder: nextSortOrder + index,
                imageData: draft.data
            ))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
