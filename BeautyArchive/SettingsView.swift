import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderPreferences.leadChoiceKey) private var leadChoice = 0
    @AppStorage(ReminderPreferences.customLeadDaysKey) private var customLeadDays = 2
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isLoadingAuthorization = true
    @State private var iCloudStatus: CKAccountStatus?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var exportedURL: URL?

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
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

                    Picker("通知タイミング", selection: $leadChoice) {
                        Text("目安日当日").tag(0)
                        Text("1日前").tag(1)
                        Text("3日前").tag(3)
                        Text("7日前").tag(7)
                        Text("日数を指定").tag(-1)
                    }
                    if leadChoice == -1 {
                        Stepper("\(customLeadDays)日前", value: $customLeadDays, in: 0...365)
                    }
                    Text("通知は選んだ日の午前9時に届きます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(authorizationDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            .task { await refreshAuthorization() }
            .task { await refreshICloudStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await refreshAuthorization()
                        await refreshICloudStatus()
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
                leadChoice: leadChoice,
                customLeadDays: customLeadDays
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
