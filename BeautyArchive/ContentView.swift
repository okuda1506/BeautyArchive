import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case home
    case archive
    case calendar
    case items
}

private enum AddDestination: String, Identifiable {
    case visit
    case copiedVisit
    case product
    case salonAppointment
    case purchasePlan

    var id: String { rawValue }
}

struct ContentView: View {
    private struct ContentAlert {
        let title: String
        let message: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ReminderTimingSettings.self) private var reminderTiming
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
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
    @State private var selectedVisitID: UUID?
    @State private var selectedProductID: UUID?
    @State private var showingSettings = false
    @State private var addDestination: AddDestination?
    @State private var notificationTask: Task<Void, Never>?
    @State private var contentAlert: ContentAlert?

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
        return "\(remindersEnabled):\(reminderTiming.leadChoice):\(reminderTiming.customLeadDays):\(unitChanges):\(productChanges):\(visitChanges):\(treatmentChanges):\(appointmentChanges):\(appointmentTreatmentChanges):\(adjustmentChanges)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.home) {
                HomeView(
                    actions: actions,
                    visits: visits,
                    salonPhotos: photos,
                    salonTreatments: treatments,
                    appointments: appointments,
                    appointmentTreatments: appointmentTreatments,
                    salonReminderAdjustments: salonReminderAdjustments,
                    products: products,
                    productUnits: productUnits,
                    selectedTab: $selectedTab,
                    selectedVisitID: $selectedVisitID,
                    selectedProductID: $selectedProductID,
                    showingSettings: $showingSettings
                )
                .toolbar(.hidden, for: .tabBar)
            } label: {
                Image(systemName: "house.fill")
                    .accessibilityLabel("ホーム")
            }

            Tab(value: AppTab.archive) {
                SalonArchiveView(selectedVisitID: $selectedVisitID)
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                Image(systemName: "square.text.square")
                    .accessibilityLabel("記録")
            }

            Tab(value: AppTab.calendar) {
                AppointmentListView()
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                Image(systemName: "calendar")
                    .accessibilityLabel("予定")
            }

            Tab(value: AppTab.items) {
                ProductListView(selectedProductID: $selectedProductID)
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                Image(systemName: "bag")
                    .accessibilityLabel("アイテム")
            }

        }
        .tint(.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationBar(selectedTab: $selectedTab, canCopyVisit: !visits.isEmpty) {
                addDestination = $0
            }
        }
        .sheet(item: $addDestination) { destination in
            switch destination {
            case .visit:
                SalonVisitForm()
            case .copiedVisit:
                let latestVisit = visits.max(by: { $0.date < $1.date })
                SalonVisitForm(
                    copying: latestVisit,
                    copyingTreatments: treatments.filter { $0.visitID == latestVisit?.id }
                )
            case .product:
                ProductForm()
            case .salonAppointment:
                AppointmentForm()
            case .purchasePlan:
                PurchasePlanForm()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(showCloseButton: true)
        }
        .onAppear { scheduleNotificationReconciliation() }
        .task { await syncPendingGoogleAppointments() }
        .onChange(of: notificationSignature) { _, _ in scheduleNotificationReconciliation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleNotificationReconciliation()
                Task { await syncPendingGoogleAppointments() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .googleCalendarConnectionChanged)) { _ in
            Task { await syncPendingGoogleAppointments() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .googleCalendarSyncPersistenceFailed)) { notice in
            if let message = notice.object as? String {
                contentAlert = ContentAlert(
                    title: "Googleへの反映状態を保存できませんでした", message: message
                )
            }
        }
        .alert(contentAlert?.title ?? "", isPresented: Binding(
            get: { contentAlert != nil },
            set: { if !$0 { contentAlert = nil } }
        )) {
            Button("閉じる", role: .cancel) { contentAlert = nil }
        } message: {
            Text(contentAlert?.message ?? "")
        }
    }

    @MainActor
    private func syncPendingGoogleAppointments() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              GoogleCalendarConnection.shared.isConfigured else { return }
        if let error = await GoogleCalendarSyncService.shared.syncPending(in: modelContext),
           contentAlert == nil {
            contentAlert = ContentAlert(
                title: "Googleへの反映状態を保存できませんでした", message: error
            )
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
                choice: reminderTiming.leadChoice,
                customDays: reminderTiming.customLeadDays
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
            if let error = productError ?? salonError {
                contentAlert = ContentAlert(title: "通知を予約できませんでした", message: error)
            }
        }
    }
}

private struct BottomNavigationBar: View {
    @Binding var selectedTab: AppTab
    let canCopyVisit: Bool
    let onAdd: (AddDestination) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedTab: AppTab?
    @State private var draggedIndicatorX: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                addGlass
                    .offset(x: geometry.size.width / 2 - 30, y: 4)

                Color.clear
                    .frame(width: 54, height: 54)
                    .glassEffect(.clear, in: Circle())
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.18), .white.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                    }
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                    .offset(x: (draggedIndicatorX ?? tabCenter(selectedTab, barWidth: geometry.size.width)) - 27,
                            y: 7)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    tabButton(.home, title: "ホーム", symbol: "house", selectedSymbol: "house.fill")
                    tabButton(.archive, title: "記録", symbol: "square.text.square",
                              selectedSymbol: "square.text.square.fill")
                    addMenu
                    tabButton(.calendar, title: "カレンダー", symbol: "calendar", selectedSymbol: "calendar")
                    tabButton(.items, title: "アイテム", symbol: "bag", selectedSymbol: "bag.fill")
                }
                .frame(height: 68)
                .padding(.horizontal, 8)
                .contentShape(Capsule())
                .highPriorityGesture(tabDragGesture(barWidth: geometry.size.width))
            }
            .frame(height: 68)
            .coordinateSpace(name: "bottomNavigation")
            .animation(tabAnimation, value: selectedTab)
        }
        .frame(height: 68)
        .glassEffect(.regular, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var addGlass: some View {
        Color.clear
            .frame(width: 60, height: 60)
            .glassEffect(.regular.tint(.gray.opacity(0.38)), in: Circle())
            .overlay {
                Circle().fill(
                    RadialGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04), .clear],
                        center: .init(x: 0.25, y: 0.18),
                        startRadius: 0,
                        endRadius: 52
                    )
                )
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            .allowsHitTesting(false)
    }

    private var addMenu: some View {
        Menu {
            Button("美容院の記録", systemImage: "square.and.pencil") {
                onAdd(.visit)
            }
            if canCopyVisit {
                Button("前回から美容院の記録", systemImage: "doc.on.doc") {
                    onAdd(.copiedVisit)
                }
            }
            Button("商品", systemImage: "bag") {
                onAdd(.product)
            }
            Divider()
            Button("美容院の予定", systemImage: "scissors") {
                onAdd(.salonAppointment)
            }
            Button("購入予定", systemImage: "calendar.badge.plus") {
                onAdd(.purchasePlan)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .frame(maxWidth: .infinity)
        .tint(Color(uiColor: .label))
        .accessibilityLabel("追加")
    }

    private func tabButton(
        _ tab: AppTab, title: String, symbol: String, selectedSymbol: String
    ) -> some View {
        Button {
            withAnimation(tabAnimation) { selectedTab = tab }
        } label: {
            Image(systemName: highlightedTab == tab ? selectedSymbol : symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(highlightedTab == tab ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selectedTab == tab ? "選択中" : "")
    }

    private func tabDragGesture(barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("bottomNavigation"))
            .onChanged { value in
                guard tab(at: value.startLocation.x, barWidth: barWidth) != nil,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                let first = tabCenter(.home, barWidth: barWidth)
                let last = tabCenter(.items, barWidth: barWidth)
                let position = min(last, max(first, value.location.x))
                // Follow the finger without animating each drag update.
                draggedIndicatorX = position
                draggedTab = nearestTab(to: position, barWidth: barWidth)
            }
            .onEnded { value in
                guard tab(at: value.startLocation.x, barWidth: barWidth) != nil else { return }
                let destination = abs(value.translation.width) > abs(value.translation.height)
                    ? nearestTab(to: value.location.x, barWidth: barWidth)
                    : selectedTab
                withAnimation(tabAnimation) {
                    selectedTab = destination
                    draggedIndicatorX = nil
                    draggedTab = nil
                }
            }
    }

    private var highlightedTab: AppTab { draggedTab ?? selectedTab }

    private var tabAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)
    }

    private func tabCenter(_ tab: AppTab, barWidth: CGFloat) -> CGFloat {
        let slot: CGFloat
        switch tab {
        case .home: slot = 0
        case .archive: slot = 1
        case .calendar: slot = 3
        case .items: slot = 4
        }
        return 8 + (barWidth - 16) / 5 * (slot + 0.5)
    }

    private func nearestTab(to position: CGFloat, barWidth: CGFloat) -> AppTab {
        [.home, .archive, .calendar, .items].min {
            abs(tabCenter($0, barWidth: barWidth) - position)
                < abs(tabCenter($1, barWidth: barWidth) - position)
        } ?? .home
    }

    private func tab(at position: CGFloat, barWidth: CGFloat) -> AppTab? {
        let slotWidth = (barWidth - 16) / 5
        guard slotWidth > 0 else { return nil }
        switch Int((position - 8) / slotWidth) {
        case 0: return .home
        case 1: return .archive
        case 3: return .calendar
        case 4: return .items
        default: return nil
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
    let visits: [SalonVisit]
    let salonPhotos: [SalonPhoto]
    let salonTreatments: [SalonTreatment]
    let appointments: [BeautyAppointment]
    let appointmentTreatments: [AppointmentTreatment]
    let salonReminderAdjustments: [SalonReminderAdjustment]
    let products: [BeautyProduct]
    let productUnits: [ProductUnit]
    @Binding var selectedTab: AppTab
    @Binding var selectedVisitID: UUID?
    @Binding var selectedProductID: UUID?
    @Binding var showingSettings: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var showingAllActions = false
    @State private var showingAddVisit = false
    @State private var showingPreparation = false
    @State private var pendingPreparation = false
    @State private var editingAppointment: BeautyAppointment?
    @State private var pendingAppointment: BeautyAppointment?
    @State private var creatingAppointment: HomeAction?
    @State private var pendingNewAppointment: HomeAction?
    @State private var registeringProduct: BeautyProduct?
    @State private var pendingProductRegistration: BeautyProduct?
    @State private var completingAppointment: BeautyAppointment?
    @State private var pendingVisitAppointment: BeautyAppointment?
    @State private var homeAlert: HomeAlert?
    @State private var editingDueAction: HomeAction?
    @State private var pendingDueAction: HomeAction?
    @State private var editedDueDate = Date.now

    private var hairActions: [HomeAction] {
        actions.filter { $0.kind != .itemReplacement }
    }
    private var actionGroups: HomeActionGroups { HomeActionGroups(actions: actions) }
    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    maintenanceSection
                    ForEach(ProductCategory.allCases) { category in
                        HomeItemsSection(
                            category: category,
                            products: products,
                            units: productUnits,
                            onSelectProduct: { productID in
                                selectedProductID = productID
                                selectedTab = .items
                            },
                            onShowAll: { selectedTab = .items }
                        )
                    }
                    categorySection
                    HomeRecentRecordsSection(
                        visits: visits,
                        treatments: salonTreatments,
                        photos: salonPhotos,
                        products: products,
                        units: productUnits,
                        onSelectVisit: { visitID in
                            selectedVisitID = visitID
                            selectedTab = .archive
                        },
                        onSelectProduct: { productID in
                            selectedProductID = productID
                            selectedTab = .items
                        }
                    )
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
                } else if let pendingNewAppointment {
                    self.pendingNewAppointment = nil
                    creatingAppointment = pendingNewAppointment
                } else if let pendingProductRegistration {
                    self.pendingProductRegistration = nil
                    registeringProduct = pendingProductRegistration
                } else if let pendingVisitAppointment {
                    self.pendingVisitAppointment = nil
                    completingAppointment = pendingVisitAppointment
                    showingAddVisit = true
                } else if let pendingDueAction {
                    self.pendingDueAction = nil
                    editingDueAction = pendingDueAction
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
            .sheet(item: $creatingAppointment) { action in
                AppointmentForm(
                    suggestedTitle: "\(action.title)の予約",
                    suggestedShopName: visits.first(where: { $0.id == action.visitID })?.salonName ?? "",
                    suggestedTreatmentName: action.title
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
            VStack(alignment: .leading, spacing: 4) {
                Text("B/ONE")
                    .font(BOneTypography.brand)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Text("記録する。整える。もっと、いい自分へ。")
                    .font(.caption)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("設定")
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ヘアメンテナンス")
                        .font(BOneTypography.eyebrow)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if actions.count > 1 || (hairActions.isEmpty && !actions.isEmpty) {
                        Button("すべて見る") { showingAllActions = true }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        selectedTab = .calendar
                    } label: {
                        Image(systemName: "calendar")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("カレンダーを開く")
                }

                if let action = hairActions.first {
                    Button {
                        handle(action)
                    } label: {
                        HStack(spacing: 14) {
                            maintenancePhoto(for: action)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Hair")
                                    .font(BOneTypography.eyebrow)
                                Text(maintenanceStatus(for: action))
                                    .font(action.daysUntil(referenceDate: .now, calendar: calendar) < 0
                                        ? BOneTypography.compactCountdown : BOneTypography.countdown)
                                    .monospacedDigit()
                                Text(action.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(dateSummary(for: action))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.primary)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ヘアメンテナンス、\(action.title)、\(maintenanceStatus(for: action))")
                    .accessibilityHint(actionTitle(for: action))
                } else {
                    Button {
                        selectedTab = .archive
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "scissors")
                                .font(.title2)
                                .frame(width: 86, height: 86)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("次のヘアメンテナンスはありません")
                                    .font(BOneTypography.rowTitle)
                                Text("記録を追加すると目安を確認できます")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func maintenancePhoto(for action: HomeAction) -> some View {
        Group {
            if let photo = actionPhoto(for: action) {
                photo
                    .resizable()
                    .scaledToFill()
                    .frame(width: 86, height: 86)
                    .clipped()
            } else {
                Image(systemName: "scissors")
                    .font(.title2)
                    .frame(width: 86, height: 86)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
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
                            .font(BOneTypography.rowTitle)
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
                Menu {
                    Button("予約済みの予定を追加", systemImage: "calendar.badge.plus") {
                        recordBooking(for: action)
                    }
                    Divider()
                    adjustmentOptions(for: action)
                } label: {
                    Label("予約・目安の操作", systemImage: "ellipsis.circle")
                }
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
                .font(BOneTypography.section)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 8) {
                category("Hair", imageName: "HomeCategoryHair", tab: .archive)
                category("Cosmetics", imageName: "HomeCategoryCosmetics", tab: .items)
                category("Fragrance", imageName: "HomeCategoryFragrance", tab: .items)
            }
        }
    }

    private func category(
        _ title: String, imageName: String, tab: AppTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color(uiColor: .tertiarySystemGroupedBackground)
                    GeometryReader { geometry in
                        Image(imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                }
                .frame(height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title == "Fragrance" ? "香水" : title)を開く")
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
            List {
                if !actionGroups.needsAttention.isEmpty {
                    Section("期限超過・記録待ち") {
                        ForEach(actionGroups.needsAttention) { compactAction($0) }
                    }
                }
                if !actionGroups.withinSevenDays.isEmpty {
                    Section("7日以内") {
                        ForEach(actionGroups.withinSevenDays) { compactAction($0) }
                    }
                }
                if !actionGroups.later.isEmpty {
                    Section("それ以降") {
                        ForEach(actionGroups.later) { compactAction($0) }
                    }
                }
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

    private func maintenanceStatus(for action: HomeAction) -> String {
        action.kind == .salonNeedsRecord ? "記録待ち" : relativeSummary(for: action)
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
            guard let appointment = appointments.first(where: { $0.id == action.id }) else { return }
            if wasShowingAllActions {
                pendingVisitAppointment = appointment
            } else {
                completingAppointment = appointment
                showingAddVisit = true
            }
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

    private func recordBooking(for action: HomeAction) {
        guard action.kind == .salonNeedsBooking else { return }
        if showingAllActions {
            pendingNewAppointment = action
            showingAllActions = false
        } else {
            creatingAppointment = action
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
            adjustmentOptions(for: action)
        } label: {
            Label("今回は見送る", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("\(action.title)の通知・目安を調整")
    }

    @ViewBuilder
    private func adjustmentOptions(for action: HomeAction) -> some View {
        Button("1週間後に知らせる", systemImage: "clock.arrow.circlepath") {
            postponeReminder(for: action)
        }
        .disabled(!remindersEnabled)
        if !remindersEnabled {
            Text("通知は設定でオンにできます")
        }
        Button("今回の目安日を変更", systemImage: "calendar.badge.clock") {
            editDueDate(for: action)
        }
        if activeAdjustment(for: action) != nil {
            Button("調整を解除", systemImage: "arrow.uturn.backward", role: .destructive) {
                clearAdjustment(for: action)
            }
        }
    }

    private func editDueDate(for action: HomeAction) {
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
        ) ?? .now
        editedDueDate = max(action.date, tomorrow)
        if showingAllActions {
            pendingDueAction = action
            showingAllActions = false
        } else {
            editingDueAction = action
        }
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
        .environment(ReminderTimingSettings(syncEnabled: false))
        .modelContainer(for: [
            SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
            HairStyleReference.self, ReferencePhoto.self,
            BeautyAppointment.self, AppointmentTreatment.self, GoogleAppointmentLink.self,
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
    .environment(ReminderTimingSettings(syncEnabled: false))
    .modelContainer(for: [
        SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
        HairStyleReference.self, ReferencePhoto.self,
        BeautyAppointment.self, AppointmentTreatment.self, GoogleAppointmentLink.self,
        BeautyProduct.self, ProductUnit.self,
        SalonReminderAdjustment.self
    ], inMemory: true)
}
