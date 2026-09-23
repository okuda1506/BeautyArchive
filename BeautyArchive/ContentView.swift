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
    private let previewActions: [HomeAction]?
    @Query private var visits: [SalonVisit]
    @Query private var treatments: [SalonTreatment]
    @Query private var photos: [SalonPhoto]
    @State private var selectedTab: AppTab = .home

    init(actions: [HomeAction]? = nil) {
        self.previewActions = actions
    }

    private var actions: [HomeAction] {
        previewActions ?? SalonMaintenance.actions(
            visits: visits, treatments: treatments, photos: photos
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: AppTab.home) {
                HomeView(actions: actions, selectedTab: $selectedTab)
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
                DestinationPlaceholder(title: "アイテム", symbol: "bag")
            } label: {
                Image(systemName: "bag")
                    .accessibilityLabel("アイテム")
            }

            Tab(value: AppTab.settings) {
                DestinationPlaceholder(title: "設定", symbol: "gearshape")
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("設定")
            }
        }
        .tint(.primary)
    }
}

private struct DestinationPlaceholder: View {
    let title: String
    let symbol: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "準備中",
                systemImage: symbol,
                description: Text("\(title)の機能は今後追加します。")
            )
            .navigationTitle(title)
        }
    }
}

private struct HomeView: View {
    let actions: [HomeAction]
    @Binding var selectedTab: AppTab
    @Environment(\.openURL) private var openURL
    @State private var showingAllActions = false
    @State private var showingAddVisit = false
    @State private var showingLinkNotice = false

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
            .sheet(isPresented: $showingAllActions) {
                allActionsSheet
            }
            .sheet(isPresented: $showingAddVisit) {
                SalonVisitForm()
            }
            .alert("予約先が未登録です", isPresented: $showingLinkNotice) {
                Button("閉じる", role: .cancel) { }
            } message: {
                Text("記録に予約先のURLを登録すると、ここから開けるようになります。")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beauty Archive")
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

                if action.kind == .salonNeedsBooking {
                    Button("前回の記録", systemImage: "chevron.right") {
                        selectedTab = .archive
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
        case .salonNeedsBooking: return "次回目安 \(dateText)"
        case .salonBooked: return "予約済み · \(dateText)"
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
        case .itemReplacement: "商品を見る"
        }
    }

    private func actionSymbol(for action: HomeAction) -> String {
        switch action.kind {
        case .salonNeedsBooking: "calendar"
        case .salonBooked: "square.text.square"
        case .itemReplacement: "bag"
        }
    }

    private func handle(_ action: HomeAction) {
        showingAllActions = false
        switch action.kind {
        case .salonNeedsBooking:
            if let url = action.destinationURL { openURL(url) }
            else { showingLinkNotice = true }
        case .salonBooked:
            selectedTab = .archive
        case .itemReplacement:
            selectedTab = .items
        }
    }
}

#Preview("Empty") {
    ContentView()
        .modelContainer(for: [
            SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
            HairStyleReference.self, ReferencePhoto.self,
            BeautyAppointment.self, AppointmentTreatment.self
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
        BeautyAppointment.self, AppointmentTreatment.self
    ], inMemory: true)
}
