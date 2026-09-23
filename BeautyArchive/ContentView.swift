import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case home
    case archive
    case calendar
    case items
    case settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderPreferences.leadChoiceKey) private var leadChoice = 0
    @AppStorage(ReminderPreferences.customLeadDaysKey) private var customLeadDays = 2
    private let previewActions: [HomeAction]?
    @Query private var visits: [SalonVisit]
    @Query private var treatments: [SalonTreatment]
    @Query private var photos: [SalonPhoto]
    @Query private var appointments: [BeautyAppointment]
    @Query private var appointmentTreatments: [AppointmentTreatment]
    @Query private var salonReminderAdjustments: [SalonReminderAdjustment]
    @Query private var products: [BeautyProduct]
    @Query private var productUnits: [ProductUnit]
    @State private var selectedTab: AppTab = .home
    @State private var selectedProductID: UUID?
    @State private var notificationTask: Task<Void, Never>?
    @State private var notificationError: String?

    init(actions: [HomeAction]? = nil) {
        self.previewActions = actions
    }

    private var actions: [HomeAction] {
        if let previewActions { return previewActions }
        let salonActions = SalonMaintenance.actions(
            visits: visits,
            treatments: treatments,
            photos: photos,
            appointments: appointments,
            appointmentTreatments: appointmentTreatments,
            reminderAdjustments: salonReminderAdjustments
        )
        let replacementActions = ProductReplacementActions.actions(products: products, units: productUnits)
        return (salonActions + replacementActions).sorted { $0.date < $1.date }
    }

    private var notificationSignature: String {
        let unitChanges = productUnits.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.wantsReplacementNotification)"
        }.sorted().joined(separator: "|")
        let productChanges = products.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)"
        }.sorted().joined(separator: "|")
        let visitChanges = visits.map {
            "\($0.id.uuidString):\($0.date.timeIntervalSince1970)"
        }.sorted().joined(separator: "|")
        let treatmentChanges = treatments.map {
            "\($0.id.uuidString):\($0.visitID.uuidString):\($0.name):\($0.cycleDays)"
        }.sorted().joined(separator: "|")
        let appointmentChanges = appointments.map {
            "\($0.id.uuidString):\($0.startAt.timeIntervalSince1970):\($0.statusRaw):\($0.completedVisitID?.uuidString ?? "")"
        }.sorted().joined(separator: "|")
        let appointmentTreatmentChanges = appointmentTreatments.map {
            "\($0.id.uuidString):\($0.appointmentID.uuidString):\($0.name)"
        }.sorted().joined(separator: "|")
        let adjustmentChanges = salonReminderAdjustments.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.baseDueDate.timeIntervalSince1970):\($0.overrideDueDate?.timeIntervalSince1970 ?? 0):\($0.snoozedUntil?.timeIntervalSince1970 ?? 0)"
        }.sorted().joined(separator: "|")
        return "\(remindersEnabled):\(leadChoice):\(customLeadDays):\(unitChanges):\(productChanges):\(visitChanges):\(treatmentChanges):\(appointmentChanges):\(appointmentTreatmentChanges):\(adjustmentChanges)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.home) {
                HomeView(
                    actions: actions,
                    appointments: appointments,
                    appointmentTreatments: appointmentTreatments,
                    salonReminderAdjustments: salonReminderAdjustments,
                    products: products,
                    selectedTab: $selectedTab,
                    selectedProductID: $selectedProductID
                )
            } label: {
                Image(systemName: "house.fill")
                    .accessibilityLabel("ホーム")
            }

            Tab(value: AppTab.archive) {
                SalonArchiveView()
            } label: {
                Image(systemName: "square.text.square")
                    .accessibilityLabel("記録")
            }

            Tab(value: AppTab.calendar) {
                AppointmentListView()
            } label: {
                Image(systemName: "calendar")
                    .accessibilityLabel("予定")
            }

            Tab(value: AppTab.items) {
                ProductListView(selectedProductID: $selectedProductID)
            } label: {
                Image(systemName: "bag")
                    .accessibilityLabel("アイテム")
            }

            Tab(value: AppTab.settings) {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("設定")
            }
        }
        .tint(.primary)
        .onAppear { scheduleNotificationReconciliation() }
        .onChange(of: notificationSignature) { _, _ in scheduleNotificationReconciliation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scheduleNotificationReconciliation() }
        }
        .alert("通知を予約できませんでした", isPresented: Binding(
            get: { notificationError != nil },
            set: { if !$0 { notificationError = nil } }
        )) {
            Button("閉じる", role: .cancel) { notificationError = nil }
        } message: {
            Text(notificationError ?? "")
        }
    }

    @MainActor
    private func scheduleNotificationReconciliation() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        let previousTask = notificationTask
        previousTask?.cancel()
        notificationTask = Task {
            await previousTask?.value
            let leadDays = ReminderPreferences.effectiveLeadDays(
                choice: leadChoice, customDays: customLeadDays
            )
            let productError = await ProductNotificationScheduler.reconcile(
                products: products,
                units: productUnits,
                enabled: remindersEnabled,
                leadDays: leadDays
            )
            guard !Task.isCancelled else { return }
            let salonError = await SalonNotificationScheduler.reconcile(
                visits: visits,
                treatments: treatments,
                appointments: appointments,
                appointmentTreatments: appointmentTreatments,
                reminderAdjustments: salonReminderAdjustments,
                enabled: remindersEnabled,
                leadDays: leadDays
            )
            guard !Task.isCancelled else { return }
            if let error = productError ?? salonError { notificationError = error }
        }
    }
}

private struct HomeView: View {
    private enum HomeAlert {
        case missingBookingURL
        case adjustmentFailure(String)

        var title: String {
            switch self {
            case .missingBookingURL: "予約先が未登録です"
            case .adjustmentFailure: "目安を変更できませんでした"
            }
        }

        var message: String {
            switch self {
            case .missingBookingURL: "記録に予約先のURLを登録すると、ここから開けるようになります。"
            case .adjustmentFailure(let detail): detail
            }
        }
    }

    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    let actions: [HomeAction]
    let appointments: [BeautyAppointment]
    let appointmentTreatments: [AppointmentTreatment]
    let salonReminderAdjustments: [SalonReminderAdjustment]
    let products: [BeautyProduct]
    @Binding var selectedTab: AppTab
    @Binding var selectedProductID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingAllActions = false
    @State private var showingAddVisit = false
    @State private var showingPreparation = false
    @State private var pendingPreparation = false
    @State private var editingAppointment: BeautyAppointment?
    @State private var pendingAppointment: BeautyAppointment?
    @State private var registeringProduct: BeautyProduct?
    @State private var pendingProductRegistration: BeautyProduct?
    @State private var completingAppointment: BeautyAppointment?
    @State private var homeAlert: HomeAlert?
    @State private var editingDueAction: HomeAction?
    @State private var editedDueDate = Date.now

    private var upcoming: [HomeAction] { HomeAction.upcoming(from: actions) }
    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    maintenanceSection
                    categorySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAllActions, onDismiss: {
                if pendingPreparation {
                    pendingPreparation = false
                    showingPreparation = true
                } else if let pendingAppointment {
                    self.pendingAppointment = nil
                    editingAppointment = pendingAppointment
                } else if let pendingProductRegistration {
                    self.pendingProductRegistration = nil
                    registeringProduct = pendingProductRegistration
                }
            }) {
                allActionsSheet
            }
            .sheet(isPresented: $showingAddVisit) {
                SalonVisitForm(
                    completingAppointment: completingAppointment,
                    appointmentTreatments: appointmentTreatments.filter {
                        $0.appointmentID == completingAppointment?.id
                    }
                )
            }
            .sheet(item: $editingDueAction) { action in
                dueDateEditor(for: action)
            }
            .sheet(isPresented: $showingPreparation) {
                StylistPreparationPicker()
            }
            .sheet(item: $editingAppointment) { appointment in
                AppointmentForm(
                    appointment: appointment,
                    treatments: appointmentTreatments.filter { $0.appointmentID == appointment.id }
                )
            }
            .sheet(item: $registeringProduct) { product in
                ProductUnitForm(product: product)
            }
            .alert(homeAlert?.title ?? "", isPresented: Binding(
                get: { homeAlert != nil },
                set: { if !$0 { homeAlert = nil } }
            )) {
                Button("閉じる", role: .cancel) { homeAlert = nil }
            } message: {
                Text(homeAlert?.message ?? "")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("B/ONE")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Text(Date.now.formatted(
                    .dateTime.month().day().weekday(.abbreviated)
                        .locale(Locale(identifier: "ja_JP"))
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                completingAppointment = nil
                showingAddVisit = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("記録を追加")
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("次のメンテナンス")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !actions.isEmpty {
                    Button("すべて見る", systemImage: "chevron.right") {
                        showingAllActions = true
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if let first = upcoming.first {
                featuredAction(first)
                ForEach(upcoming.dropFirst()) { action in
                    compactAction(action)
                }
            } else {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "square.stack",
                    description: Text("美容院の記録やアイテムを追加すると、次の行動がここに表示されます。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
        }
    }

    private func featuredAction(_ action: HomeAction) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                Group {
                    if let photo = actionPhoto(for: action) {
                        photo
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: action.kind == .itemReplacement ? "bag" : "scissors")
                                    .font(.system(size: 46, weight: .ultraLight))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            }
            .frame(height: 190)
            .accessibilityHidden(true)

            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(action.title)
                            .font(.title3.bold())
                        Text(dateSummary(for: action))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if action.kind == .salonNeedsBooking {
                        Text(relativeSummary(for: action))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }

                Button {
                    handle(action)
                } label: {
                    Label(actionTitle(for: action), systemImage: actionSymbol(for: action))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: .label))

                if action.kind == .itemReplacement {
                    Button("買い直しを記録", systemImage: "plus") {
                        registerReplacement(for: action)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let url = action.destinationURL {
                        Button("もう一度購入", systemImage: "arrow.up.right") {
                            openURL(url)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                if action.kind == .salonNeedsBooking {
                    Button("前回の記録", systemImage: "chevron.right") {
                        selectedTab = .archive
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if action.baselineDate != nil {
                        adjustmentMenu(for: action)
                            .font(.subheadline)
                    }
                }
                if action.kind == .salonBooked || action.kind == .salonNeedsRecord {
                    Button("予定を変更・キャンセル", systemImage: "calendar.badge.clock") {
                        editAppointment(for: action)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func compactAction(_ action: HomeAction) -> some View {
        HStack(spacing: 0) {
            Button {
                handle(action)
            } label: {
                HStack(spacing: 14) {
                    if let photo = actionPhoto(for: action) {
                        photo
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: action.kind == .itemReplacement ? "bag" : "scissors")
                            .font(.title2)
                            .frame(width: 64, height: 64)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(dateSummary(for: action))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let detail = action.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action.title)、\(dateSummary(for: action))、\(actionTitle(for: action))")

            if action.kind == .salonNeedsBooking, action.baselineDate != nil {
                adjustmentMenu(for: action)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            } else if action.kind == .salonBooked || action.kind == .salonNeedsRecord {
                Menu {
                    Button("予定を変更・キャンセル", systemImage: "calendar.badge.clock") {
                        editAppointment(for: action)
                    }
                } label: {
                    Label("予定の操作", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            } else if action.kind == .itemReplacement {
                Menu {
                    Button("買い直しを記録", systemImage: "plus") {
                        registerReplacement(for: action)
                    }
                } label: {
                    Label("買い替えの操作", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("カテゴリ")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                category("Hair", symbol: "scissors", tab: .archive)
                category("Cosmetics", symbol: "bag", tab: .items)
                category("香水", symbol: "sparkles", tab: .items)
            }
        }
    }

    private func category(_ title: String, symbol: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.title2)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 78)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)を開く")
    }

    private func actionPhoto(for action: HomeAction) -> Image? {
        if let data = action.imageData, let image = UIImage(data: data) {
            return Image(uiImage: image)
        }
        if let imageName = action.imageName { return Image(imageName) }
        return nil
    }

    private var allActionsSheet: some View {
        NavigationStack {
            List(actions.sorted { $0.date < $1.date }) { action in
                compactAction(action)
            }
            .navigationTitle("次のメンテナンス")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showingAllActions = false }
                }
            }
        }
    }

    private func dateSummary(for action: HomeAction) -> String {
        let dateText = action.date.formatted(
            .dateTime.month().day().locale(Locale(identifier: "ja_JP"))
        )
        switch action.kind {
        case .salonNeedsBooking:
            let label = action.hasDueDateOverride ? "今回の目安" : "次回目安"
            if remindersEnabled, let reminderDate = action.snoozedReminderDate {
                let reminderText = reminderDate.formatted(
                    .dateTime.month().day().locale(Locale(identifier: "ja_JP"))
                )
                return "\(label) \(dateText) · \(reminderText)に再通知"
            }
            return "\(label) \(dateText)"
        case .salonBooked:
            return "予約済み · \(action.date.formatted(.dateTime.month().day().hour().minute()))"
        case .salonNeedsRecord: return "予約日時を経過 · \(dateText)"
        case .itemReplacement: return "買い替え目安 \(dateText)"
        }
    }

    private func relativeSummary(for action: HomeAction) -> String {
        let days = action.daysUntil(referenceDate: .now, calendar: calendar)
        if days < 0 { return "目安を過ぎました" }
        if days == 0 { return "今日" }
        return "あと\(days)日"
    }

    private func actionTitle(for action: HomeAction) -> String {
        switch action.kind {
        case .salonNeedsBooking: "予約する"
        case .salonBooked: "オーダーを準備"
        case .salonNeedsRecord: "来店を記録"
        case .itemReplacement: "商品を見る"
        }
    }

    private func actionSymbol(for action: HomeAction) -> String {
        switch action.kind {
        case .salonNeedsBooking: "calendar"
        case .salonBooked: "square.text.square"
        case .salonNeedsRecord: "square.and.pencil"
        case .itemReplacement: "bag"
        }
    }

    private func handle(_ action: HomeAction) {
        let wasShowingAllActions = showingAllActions
        showingAllActions = false
        switch action.kind {
        case .salonNeedsBooking:
            if let url = action.destinationURL { openURL(url) }
            else { homeAlert = .missingBookingURL }
        case .salonBooked:
            if wasShowingAllActions { pendingPreparation = true }
            else { showingPreparation = true }
        case .salonNeedsRecord:
            completingAppointment = appointments.first { $0.id == action.id }
            showingAddVisit = true
        case .itemReplacement:
            selectedProductID = action.productID
            selectedTab = .items
        }
    }

    private func editAppointment(for action: HomeAction) {
        guard let appointment = appointments.first(where: { $0.id == action.id }) else { return }
        if showingAllActions {
            pendingAppointment = appointment
            showingAllActions = false
        } else {
            editingAppointment = appointment
        }
    }

    private func registerReplacement(for action: HomeAction) {
        guard let productID = action.productID,
              let product = products.first(where: { $0.id == productID }) else { return }
        if showingAllActions {
            pendingProductRegistration = product
            showingAllActions = false
        } else {
            registeringProduct = product
        }
    }

    private func adjustmentMenu(for action: HomeAction) -> some View {
        Menu {
            Button("1週間後に知らせる", systemImage: "clock.arrow.circlepath") {
                postponeReminder(for: action)
            }
            .disabled(!remindersEnabled)
            if !remindersEnabled {
                Text("通知は設定でオンにできます")
            }
            Button("今回の目安日を変更", systemImage: "calendar.badge.clock") {
                let tomorrow = calendar.date(
                    byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
                ) ?? .now
                editedDueDate = max(action.date, tomorrow)
                editingDueAction = action
            }
            if activeAdjustment(for: action) != nil {
                Button("調整を解除", systemImage: "arrow.uturn.backward", role: .destructive) {
                    clearAdjustment(for: action)
                }
            }
        } label: {
            Label("今回は見送る", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("\(action.title)の通知・目安を調整")
    }

    private func dueDateEditor(for action: HomeAction) -> some View {
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
        ) ?? .now
        return NavigationStack {
            Form {
                DatePicker("今回の次回目安", selection: $editedDueDate,
                           in: tomorrow..., displayedComponents: .date)
                Text("今回の目安日だけを変更します。施術履歴と通常の周期は変わりません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("次回目安を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { editingDueAction = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        updateAdjustment(for: action) { adjustment in
                            adjustment.overrideDueDate = calendar.startOfDay(for: editedDueDate)
                            adjustment.snoozedUntil = nil
                        }
                        editingDueAction = nil
                    }
                }
            }
        }
    }

    private func activeAdjustment(for action: HomeAction) -> SalonReminderAdjustment? {
        guard let baselineDate = action.baselineDate else { return nil }
        return salonReminderAdjustments
            .filter {
                $0.treatmentID == action.id
                    && calendar.isDate($0.baseDueDate, inSameDayAs: baselineDate)
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func postponeReminder(for action: HomeAction) {
        let nextWeek = calendar.date(
            byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)
        ) ?? .now
        updateAdjustment(for: action) { $0.snoozedUntil = nextWeek }
    }

    private func updateAdjustment(
        for action: HomeAction,
        change: (SalonReminderAdjustment) -> Void
    ) {
        guard let baselineDate = action.baselineDate else { return }
        let existing = salonReminderAdjustments.first { $0.treatmentID == action.id }
        let adjustment = existing ?? SalonReminderAdjustment(
            treatmentID: action.id, baseDueDate: baselineDate
        )
        if existing == nil { modelContext.insert(adjustment) }
        if !calendar.isDate(adjustment.baseDueDate, inSameDayAs: baselineDate) {
            adjustment.baseDueDate = baselineDate
            adjustment.overrideDueDate = nil
            adjustment.snoozedUntil = nil
        }
        change(adjustment)
        adjustment.updatedAt = .now
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            homeAlert = .adjustmentFailure(error.localizedDescription)
        }
    }

    private func clearAdjustment(for action: HomeAction) {
        guard let adjustment = activeAdjustment(for: action) else { return }
        modelContext.delete(adjustment)
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            homeAlert = .adjustmentFailure(error.localizedDescription)
        }
    }
}

#Preview("Empty") {
    ContentView()
        .modelContainer(for: [
            SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
            HairStyleReference.self, ReferencePhoto.self,
            BeautyAppointment.self, AppointmentTreatment.self,
            BeautyProduct.self, ProductUnit.self,
            SalonReminderAdjustment.self
        ], inMemory: true)
}

#Preview("Upcoming actions") {
    let calendar = Calendar.current
    ContentView(actions: [
        HomeAction(
            kind: .salonNeedsBooking,
            title: "カット",
            date: calendar.date(byAdding: .day, value: 2, to: .now) ?? .now,
            imageName: "PreviewHair"
        ),
        HomeAction(
            kind: .salonBooked,
            title: "カラー",
            date: calendar.date(byAdding: .day, value: 6, to: .now) ?? .now,
            imageName: "PreviewHair",
            detail: "オーダーを準備"
        ),
        HomeAction(
            kind: .itemReplacement,
            title: "美容液",
            date: calendar.date(byAdding: .day, value: 8, to: .now) ?? .now,
            detail: "使用履歴から予測"
        )
    ])
    .modelContainer(for: [
        SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
        HairStyleReference.self, ReferencePhoto.self,
        BeautyAppointment.self, AppointmentTreatment.self,
        BeautyProduct.self, ProductUnit.self,
        SalonReminderAdjustment.self
    ], inMemory: true)
}
