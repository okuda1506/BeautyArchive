import Foundation
import SwiftData

nonisolated struct BeautyArchiveExport: Encodable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let salonVisits: [SalonVisitEntry]
    let salonTreatments: [SalonTreatmentEntry]
    let salonPhotos: [SalonPhotoEntry]
    let hairReferences: [HairReferenceEntry]
    let referencePhotos: [ReferencePhotoEntry]
    let products: [ProductEntry]
    let productUnits: [ProductUnitEntry]
    let purchasePlans: [PurchasePlanEntry]
    let appointments: [AppointmentEntry]
    let appointmentTreatments: [AppointmentTreatmentEntry]
    let googleAppointmentLinks: [GoogleAppointmentLinkEntry]
    let salonReminderAdjustments: [SalonReminderAdjustmentEntry]
    let reminderSettings: ReminderSettingsEntry

    @MainActor
    init(
        context: ModelContext,
        remindersEnabled: Bool,
        leadChoice: Int,
        customLeadDays: Int
    ) throws {
        schemaVersion = 4
        exportedAt = .now
        salonVisits = try context.fetch(FetchDescriptor<SalonVisit>()).map(SalonVisitEntry.init)
        salonTreatments = try context.fetch(FetchDescriptor<SalonTreatment>()).map(SalonTreatmentEntry.init)
        salonPhotos = try context.fetch(FetchDescriptor<SalonPhoto>()).map { photo in
            guard !photo.imageData.isEmpty else { throw ExportError.unavailablePhoto }
            return SalonPhotoEntry(photo)
        }
        hairReferences = try context.fetch(FetchDescriptor<HairStyleReference>()).map(HairReferenceEntry.init)
        referencePhotos = try context.fetch(FetchDescriptor<ReferencePhoto>()).map { photo in
            guard !photo.imageData.isEmpty else { throw ExportError.unavailablePhoto }
            return ReferencePhotoEntry(photo)
        }
        products = try context.fetch(FetchDescriptor<BeautyProduct>()).map(ProductEntry.init)
        productUnits = try context.fetch(FetchDescriptor<ProductUnit>()).map(ProductUnitEntry.init)
        purchasePlans = try context.fetch(FetchDescriptor<ProductPurchasePlan>())
            .map(PurchasePlanEntry.init)
        appointments = try context.fetch(FetchDescriptor<BeautyAppointment>()).map(AppointmentEntry.init)
        appointmentTreatments = try context.fetch(FetchDescriptor<AppointmentTreatment>())
            .map(AppointmentTreatmentEntry.init)
        googleAppointmentLinks = try context.fetch(FetchDescriptor<GoogleAppointmentLink>())
            .map(GoogleAppointmentLinkEntry.init)
        salonReminderAdjustments = try context.fetch(FetchDescriptor<SalonReminderAdjustment>())
            .map(SalonReminderAdjustmentEntry.init)
        reminderSettings = ReminderSettingsEntry(
            enabledOnThisDevice: remindersEnabled,
            leadChoice: leadChoice,
            customLeadDays: customLeadDays
        )
    }

    func writeFile() async throws -> URL {
        try await Task.detached(priority: .userInitiated) { [self] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            encoder.dataEncodingStrategy = .base64
            let data = try encoder.encode(self)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmm"
            let name = "B-ONE-\(formatter.string(from: exportedAt))-\(UUID().uuidString.prefix(6)).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }.value
    }

    struct SalonVisitEntry: Encodable, Sendable {
        let id: UUID
        let date: Date
        let salonName: String
        let stylistName: String
        let orderNote: String
        let impression: String
        let nextVisitNote: String
        let bookingURL: String
        let price: Int?

        init(_ value: SalonVisit) {
            id = value.id
            date = value.date
            salonName = value.salonName
            stylistName = value.stylistName
            orderNote = value.orderNote
            impression = value.impression
            nextVisitNote = value.nextVisitNote
            bookingURL = value.bookingURL
            price = value.price
        }
    }

    struct SalonTreatmentEntry: Encodable, Sendable {
        let id: UUID
        let visitID: UUID
        let name: String
        let cycleDays: Int

        init(_ value: SalonTreatment) {
            id = value.id
            visitID = value.visitID
            name = value.name
            cycleDays = value.cycleDays
        }
    }

    struct SalonPhotoEntry: Encodable, Sendable {
        let id: UUID
        let visitID: UUID
        let sortOrder: Int
        let imageData: Data

        init(_ value: SalonPhoto) {
            id = value.id
            visitID = value.visitID
            sortOrder = value.sortOrder
            imageData = value.imageData
        }
    }

    struct HairReferenceEntry: Encodable, Sendable {
        let id: UUID
        let title: String
        let memo: String
        let sourceURL: String
        let createdAt: Date
        let updatedAt: Date

        init(_ value: HairStyleReference) {
            id = value.id
            title = value.title
            memo = value.memo
            sourceURL = value.sourceURL
            createdAt = value.createdAt
            updatedAt = value.updatedAt
        }
    }

    struct ReferencePhotoEntry: Encodable, Sendable {
        let id: UUID
        let referenceID: UUID
        let sortOrder: Int
        let imageData: Data

        init(_ value: ReferencePhoto) {
            id = value.id
            referenceID = value.referenceID
            sortOrder = value.sortOrder
            imageData = value.imageData
        }
    }

    struct ProductEntry: Encodable, Sendable {
        let id: UUID
        let name: String
        let brand: String
        let categoryRaw: String
        let purchaseURL: String
        let note: String
        let imageData: Data
        let createdAt: Date
        let updatedAt: Date

        init(_ value: BeautyProduct) {
            id = value.id
            name = value.name
            brand = value.brand
            categoryRaw = value.categoryRaw
            purchaseURL = value.purchaseURL
            note = value.note
            imageData = value.imageData
            createdAt = value.createdAt
            updatedAt = value.updatedAt
        }
    }

    struct ProductUnitEntry: Encodable, Sendable {
        let id: UUID
        let productID: UUID
        let purchasedAt: Date?
        let openedAt: Date?
        let finishedAt: Date?
        let priceYen: Int?
        let purchasedFrom: String
        let statusRaw: String
        let note: String
        let usesReplacementEstimate: Bool
        let manualUsageDays: Int?
        let adjustedUsageDays: Int?
        let wantsReplacementNotification: Bool
        let createdAt: Date
        let updatedAt: Date

        init(_ value: ProductUnit) {
            id = value.id
            productID = value.productID
            purchasedAt = value.purchasedAt
            openedAt = value.openedAt
            finishedAt = value.finishedAt
            priceYen = value.priceYen
            purchasedFrom = value.purchasedFrom
            statusRaw = value.statusRaw
            note = value.note
            usesReplacementEstimate = value.usesReplacementEstimate
            manualUsageDays = value.manualUsageDays
            adjustedUsageDays = value.adjustedUsageDays
            wantsReplacementNotification = value.wantsReplacementNotification
            createdAt = value.createdAt
            updatedAt = value.updatedAt
        }
    }

    struct PurchasePlanEntry: Encodable, Sendable {
        let id: UUID
        let productID: UUID?
        let productName: String
        let categoryRaw: String
        let plannedAt: Date
        let hasTime: Bool
        let vendor: String
        let purchaseURL: String
        let note: String
        let statusRaw: String
        let purchasedAt: Date?
        let completedUnitID: UUID?
        let createdAt: Date
        let updatedAt: Date

        init(_ value: ProductPurchasePlan) {
            id = value.id
            productID = value.productID
            productName = value.productName
            categoryRaw = value.categoryRaw
            plannedAt = value.plannedAt
            hasTime = value.hasTime
            vendor = value.vendor
            purchaseURL = value.purchaseURL
            note = value.note
            statusRaw = value.statusRaw
            purchasedAt = value.purchasedAt
            completedUnitID = value.completedUnitID
            createdAt = value.createdAt
            updatedAt = value.updatedAt
        }
    }

    struct AppointmentEntry: Encodable, Sendable {
        let id: UUID
        let title: String
        let startAt: Date
        let endAt: Date
        let shopName: String
        let note: String
        let statusRaw: String
        let completedVisitID: UUID?
        let createdAt: Date
        let updatedAt: Date

        init(_ value: BeautyAppointment) {
            id = value.id
            title = value.title
            startAt = value.startAt
            endAt = value.endAt
            shopName = value.shopName
            note = value.note
            statusRaw = value.statusRaw
            completedVisitID = value.completedVisitID
            createdAt = value.createdAt
            updatedAt = value.updatedAt
        }
    }

    struct AppointmentTreatmentEntry: Encodable, Sendable {
        let id: UUID
        let appointmentID: UUID
        let name: String

        init(_ value: AppointmentTreatment) {
            id = value.id
            appointmentID = value.appointmentID
            name = value.name
        }
    }

    struct GoogleAppointmentLinkEntry: Encodable, Sendable {
        let id: UUID
        let appointmentID: UUID
        let accountSubject: String
        let calendarID: String
        let eventID: String
        let title: String
        let startAt: Date
        let endAt: Date
        let shopName: String
        let note: String
        let stateRaw: String
        let lastError: String?
        let revision: UUID
        let updatedAt: Date

        init(_ value: GoogleAppointmentLink) {
            id = value.id
            appointmentID = value.appointmentID
            accountSubject = value.accountSubject
            calendarID = value.calendarID
            eventID = value.eventID
            title = value.title
            startAt = value.startAt
            endAt = value.endAt
            shopName = value.shopName
            note = value.note
            stateRaw = value.stateRaw
            lastError = value.lastError
            revision = value.revision
            updatedAt = value.updatedAt
        }
    }

    struct ReminderSettingsEntry: Encodable, Sendable {
        let enabledOnThisDevice: Bool
        let leadChoice: Int
        let customLeadDays: Int
    }

    struct SalonReminderAdjustmentEntry: Encodable, Sendable {
        let id: UUID
        let treatmentID: UUID
        let baseDueDate: Date
        let overrideDueDate: Date?
        let snoozedUntil: Date?
        let updatedAt: Date

        init(_ value: SalonReminderAdjustment) {
            id = value.id
            treatmentID = value.treatmentID
            baseDueDate = value.baseDueDate
            overrideDueDate = value.overrideDueDate
            snoozedUntil = value.snoozedUntil
            updatedAt = value.updatedAt
        }
    }

    private enum ExportError: LocalizedError {
        case unavailablePhoto

        var errorDescription: String? {
            "保存済みの写真を読み込めませんでした。同期が完了してからもう一度お試しください。"
        }
    }
}
