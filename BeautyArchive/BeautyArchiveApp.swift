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
    @AppStorage("onboarding.hasStarted") private var hasStarted = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderTiming = ReminderTimingSettings()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasStarted {
                    ContentView()
                } else {
                    FirstLaunchView { hasStarted = true }
                }
            }
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
        .modelContainer(for: [
            SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
            HairStyleReference.self, ReferencePhoto.self,
            BeautyAppointment.self, AppointmentTreatment.self, GoogleAppointmentLink.self,
            BeautyProduct.self, ProductUnit.self,
            SalonReminderAdjustment.self
        ])
    }
}
