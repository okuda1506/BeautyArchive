import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    var showCloseButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(ReminderTimingSettings.self) private var reminderTiming
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isLoadingAuthorization = true
    @State private var pendingReminderCount = 0
    @State private var nextReminderDate: Date?
    @State private var nextReminderTitle: String?
    @State private var isCheckingReminders = false
    @State private var reminderStatusError: String?
    @State private var iCloudStatus: CKAccountStatus?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var googleAccount: GoogleAccountIdentity?
    @State private var isLoadingGoogleAccount = true
    @State private var isGoogleBusy = false

    private let googleConnection = GoogleCalendarConnection.shared

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var reminderStatusKey: String {
        "\(remindersEnabled):\(reminderTiming.leadChoice):\(reminderTiming.customLeadDays):\(reminderTiming.notificationTimeMinutes)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("通知") {
                    Toggle("通知を受け取る", isOn: Binding(
                        get: { remindersEnabled && isAuthorized },
                        set: { enabled in
                            if enabled {
                                Task { await enableNotifications() }
                            } else {
                                remindersEnabled = false
                            }
                        }
                    ))
                    .disabled(isLoadingAuthorization)

                    Picker("目安の事前通知", selection: Binding(
                        get: { reminderTiming.leadChoice },
                        set: { reminderTiming.setLeadChoice($0) }
                    )) {
                        Text("目安日当日").tag(0)
                        Text("1日前").tag(1)
                        Text("3日前").tag(3)
                        Text("7日前").tag(7)
                        Text("日数を指定").tag(-1)
                    }
                    if reminderTiming.leadChoice == -1 {
                        Stepper("\(reminderTiming.customLeadDays)日前", value: Binding(
                            get: { reminderTiming.customLeadDays },
                            set: { reminderTiming.setCustomLeadDays($0) }
                        ), in: 0...365)
                    }
                    NavigationLink {
                        ReminderTimePickerView(initialMinutes: reminderTiming.notificationTimeMinutes) {
                            reminderTiming.setNotificationTimeMinutes($0)
                        }
                    } label: {
                        LabeledContent("通知時刻", value: ReminderTimePresentation.label(for: reminderTiming.notificationTimeMinutes))
                    }
                    Text("美容院・購入予定は前日の設定時刻に通知します。予約・買い替え目安は選んだ事前日数と設定時刻で通知します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("目安通知の「明日また通知」「1週間後に通知」で再通知を延期できます。Apple Watchに転送された通知からも操作できます。延期はこのiPhoneの通知だけに反映され、目安日は変わりません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("iCloudを利用できる場合、通知タイミングと時刻は同じApple Accountの端末へ引き継がれます。反映には時間がかかる場合があります。通知の許可とオン・オフは端末ごとです。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(authorizationDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if remindersEnabled && isAuthorized {
                        LabeledContent("予約済みの通知", value: "\(pendingReminderCount)件")
                        if let nextReminderDate, let nextReminderTitle {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("次の通知：\(nextReminderTitle)")
                                Text(nextReminderDate.japaneseFormatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        } else if !isCheckingReminders {
                            Text("通知予定はありません。未来の予約目安・買い替え目安と美容院・購入予定が対象です。商品ごとの通知設定も確認してください。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let reminderStatusError {
                            Text("通知の予約を確認できませんでした。\(reminderStatusError)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("通知予定を再確認") {
                            Task { await refreshReminderStatus() }
                        }
                        .disabled(isCheckingReminders)
                    } else {
                        Text("iPhone側の許可に加えて、この画面の「通知を受け取る」をオンにしてください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if authorizationStatus == .denied {
                        Button("端末の通知設定を開く") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                    }
                }
                Section {
                    Text("美容の目安は通知をオフにしてもHomeで確認できます。")
                        .foregroundStyle(.secondary)
                }
                Section("iCloud") {
                    Text(iCloudDescription)
                    Text("記録はこの端末に保存されます。iCloudの利用可否は同期完了や他の端末への反映を示すものではありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if googleConnection.isConfigured {
                    Section("Googleカレンダー") {
                        if isLoadingGoogleAccount {
                            ProgressView("連携状態を確認中")
                        } else if let googleAccount {
                            Label("連携済み", systemImage: "checkmark.circle.fill")
                            if let email = googleAccount.email {
                                Text(email)
                                    .foregroundStyle(.secondary)
                            }
                            Text("B/ONEで作成した美容予定は、このアプリで変更してください。Google側の変更は元の美容予定に自動反映されません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("連携を解除", role: .destructive) {
                                Task { await disconnectGoogle() }
                            }
                            .disabled(isGoogleBusy)
                        } else {
                            Text("B/ONEからGoogleカレンダーにアクセスするため、Googleアカウントの認可が必要です。")
                                .foregroundStyle(.secondary)
                            Button("Googleカレンダーと連携") {
                                Task { await connectGoogle() }
                            }
                            .disabled(isGoogleBusy)
                        }
                        if isGoogleBusy { ProgressView() }
                        Text("GoogleアカウントはB/ONEへのログインには使用しません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("データの書き出し") {
                    Button("記録と写真のファイルを作成", systemImage: "square.and.arrow.up") {
                        Task { await exportData() }
                    }
                    .disabled(isExporting)
                    if isExporting { ProgressView("ファイルを作成中") }
                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("作成したファイルを保存・共有", systemImage: "square.and.arrow.up")
                        }
                    }
                    Text("この端末で取得できる記録を書き出します。iCloudで同期中のデータは含まれない場合があります。形式はJSONで、保存済み写真をBase64データとして含みます。このファイルからのアプリ内復元は未対応です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
            .task(id: reminderStatusKey) {
                await refreshAuthorization()
                await refreshReminderStatus()
            }
            .task { await refreshICloudStatus() }
            .task { await refreshGoogleAccount() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await refreshAuthorization()
                        await refreshReminderStatus()
                        await refreshICloudStatus()
                        await refreshGoogleAccount()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                Task { await refreshICloudStatus() }
            }
            .alert("操作を完了できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func exportData() async {
        guard !isExporting else { return }
        isExporting = true
        exportedURL = nil
        defer { isExporting = false }
        do {
            let export = try BeautyArchiveExport(
                context: modelContext,
                remindersEnabled: remindersEnabled,
                leadChoice: reminderTiming.leadChoice,
                customLeadDays: reminderTiming.customLeadDays,
                notificationTimeMinutes: reminderTiming.notificationTimeMinutes
            )
            exportedURL = try await export.writeFile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined: "通知をオンにすると、端末の許可を確認します。"
        case .denied: "この端末では通知が許可されていません。"
        case .authorized, .provisional, .ephemeral: "この端末で通知が許可されています。"
        @unknown default: "通知の許可状態を確認できません。"
        }
    }

    private var iCloudDescription: String {
        switch iCloudStatus {
        case .available: "この端末ではiCloudを利用できます。"
        case .noAccount: "iCloudにサインインすると、対応端末間の同期を利用できます。"
        case .restricted: "この端末ではiCloudへのアクセスが制限されています。"
        case .temporarilyUnavailable: "iCloudは現在一時的に利用できません。"
        case .couldNotDetermine: "iCloudの利用状況を確認できませんでした。"
        case nil: "iCloudの利用状況を確認中です。"
        @unknown default: "iCloudの利用状況を確認できませんでした。"
        }
    }

    @MainActor
    private func refreshICloudStatus() async {
        do {
            iCloudStatus = try await CKContainer.default().accountStatus()
        } catch {
            iCloudStatus = .couldNotDetermine
        }
    }

    @MainActor
    private func refreshGoogleAccount() async {
        guard !isGoogleBusy else { return }
        guard googleConnection.isConfigured else {
            isLoadingGoogleAccount = false
            return
        }
        do {
            googleAccount = try await googleConnection.currentAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingGoogleAccount = false
    }

    @MainActor
    private func connectGoogle() async {
        guard !isGoogleBusy else { return }
        isGoogleBusy = true
        defer { isGoogleBusy = false }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else {
            errorMessage = GoogleOAuthBrowserError.cannotStart.localizedDescription
            return
        }
        do {
            googleAccount = try await googleConnection.connect(anchor: window)
        } catch GoogleOAuthBrowserError.cancelled {
            // A user closing the Google sheet leaves the existing connection unchanged.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func disconnectGoogle() async {
        guard !isGoogleBusy else { return }
        isGoogleBusy = true
        defer { isGoogleBusy = false }
        do {
            try await googleConnection.disconnect()
            googleAccount = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshReminderStatus() async {
        guard !isCheckingReminders else { return }
        isCheckingReminders = true
        defer { isCheckingReminders = false }
        reminderStatusError = await ReminderNotificationCoordinator.shared.reconcile()
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let reminderDates = requests.compactMap { request -> (String, Date)? in
            guard ReminderNotificationTarget.Kind.allCases.contains(where: {
                request.identifier.hasPrefix($0.identifierPrefix)
            }), let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return (request.content.title, date)
        }.sorted { $0.1 < $1.1 }
        pendingReminderCount = reminderDates.count
        nextReminderTitle = reminderDates.first?.0
        nextReminderDate = reminderDates.first?.1
    }

    @MainActor
    private func refreshAuthorization() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if !isAuthorized { remindersEnabled = false }
        isLoadingAuthorization = false
    }

    @MainActor
    private func enableNotifications() async {
        guard !isLoadingAuthorization else { return }
        if authorizationStatus == .notDetermined {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                await refreshAuthorization()
                remindersEnabled = granted && isAuthorized
            } catch {
                remindersEnabled = false
                errorMessage = error.localizedDescription
            }
        } else if isAuthorized {
            remindersEnabled = true
        } else {
            remindersEnabled = false
        }
    }
}

private enum ReminderTimePresentation {
    static func date(for minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
        ) ?? .now
    }

    static func label(for minutes: Int) -> String {
        date(for: minutes).japaneseFormatted(date: .omitted, time: .shortened)
    }
}

private struct ReminderTimePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Int) -> Void
    @State private var selectedTime: Date

    init(initialMinutes: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _selectedTime = State(initialValue: ReminderTimePresentation.date(for: initialMinutes))
    }

    var body: some View {
        Form {
            DatePicker("通知時刻", selection: $selectedTime, displayedComponents: .hourAndMinute)
            Text("このiPhoneの現地時刻で通知します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("通知時刻")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
                    guard let hour = components.hour, let minute = components.minute else { return }
                    onSave(hour * 60 + minute)
                    dismiss()
                }
            }
        }
    }
}
