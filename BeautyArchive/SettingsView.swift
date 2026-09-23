import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderPreferences.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderPreferences.leadChoiceKey) private var leadChoice = 0
    @AppStorage(ReminderPreferences.customLeadDaysKey) private var customLeadDays = 2
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isLoadingAuthorization = true
    @State private var errorMessage: String?

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
            }
            .navigationTitle("設定")
            .task { await refreshAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshAuthorization() } }
            }
            .alert("通知設定を変更できませんでした", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("閉じる", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
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
