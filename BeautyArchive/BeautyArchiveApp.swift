//
//  BeautyArchiveApp.swift
//  BeautyArchive
//
//  Created by 奥田拓也 on 2026/09/12.
//

import SwiftUI
import SwiftData

@main
struct BeautyArchiveApp: App {
    @UIApplicationDelegateAdaptor(ReminderNotificationAppDelegate.self) private var notificationDelegate
    @AppStorage("onboarding.hasStarted") private var hasStarted = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderTiming = ReminderTimingSettings()
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for:
                SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
                HairStyleReference.self, ReferencePhoto.self,
                BeautyAppointment.self, AppointmentTreatment.self, GoogleAppointmentLink.self,
                BeautyProduct.self, ProductUnit.self, ProductPurchasePlan.self,
                SalonReminderAdjustment.self
            )
        } catch {
            fatalError("B/ONEのデータストアを開けませんでした: \(error.localizedDescription)")
        }
        ReminderNotificationCoordinator.shared.configure(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            LaunchAnimationHost {
                Group {
                    if hasStarted {
                        ContentView()
                    } else {
                        FirstLaunchView { hasStarted = true }
                    }
                }
            }
            .environment(\.locale, JapanesePresentation.locale)
            .environment(reminderTiming)
            .onReceive(NotificationCenter.default.publisher(
                for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
            )) { _ in
                reminderTiming.refreshFromCloud()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reminderTiming.refreshFromCloud()
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
