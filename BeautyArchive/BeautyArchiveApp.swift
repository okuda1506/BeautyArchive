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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            SalonVisit.self, SalonTreatment.self, SalonPhoto.self,
            HairStyleReference.self, ReferencePhoto.self,
            BeautyAppointment.self, AppointmentTreatment.self,
            BeautyProduct.self, ProductUnit.self,
            SalonReminderAdjustment.self
        ])
    }
}
