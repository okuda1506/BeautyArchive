import Foundation

nonisolated struct ReminderTimingSnapshot: Codable, Equatable {
    let leadChoice: Int
    let customLeadDays: Int
    let revision: UInt64
    let deviceID: String
    let notificationTimeMinutes: Int?

    init(
        leadChoice: Int,
        customLeadDays: Int,
        revision: UInt64,
        deviceID: String,
        notificationTimeMinutes: Int? = nil
    ) {
        self.leadChoice = leadChoice
        self.customLeadDays = customLeadDays
        self.revision = revision
        self.deviceID = deviceID
        self.notificationTimeMinutes = notificationTimeMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case leadChoice, customLeadDays, revision, deviceID, notificationTimeMinutes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        leadChoice = try values.decode(Int.self, forKey: .leadChoice)
        customLeadDays = try values.decode(Int.self, forKey: .customLeadDays)
        revision = try values.decode(UInt64.self, forKey: .revision)
        deviceID = try values.decode(String.self, forKey: .deviceID)
        // Snapshots created before configurable notification times default to 9:00.
        notificationTimeMinutes = try values.decodeIfPresent(Int.self, forKey: .notificationTimeMinutes)
    }

    var isValid: Bool {
        [-1, 0, 1, 3, 7].contains(leadChoice)
            && (0...365).contains(customLeadDays)
            && (notificationTimeMinutes.map { (0..<24 * 60).contains($0) } ?? true)
            && !deviceID.isEmpty
    }

    func isNewer(than other: Self) -> Bool {
        if revision != other.revision { return revision > other.revision }
        if deviceID != other.deviceID { return deviceID > other.deviceID }
        if leadChoice != other.leadChoice { return leadChoice > other.leadChoice }
        if customLeadDays != other.customLeadDays { return customLeadDays > other.customLeadDays }
        return (notificationTimeMinutes ?? 9 * 60) > (other.notificationTimeMinutes ?? 9 * 60)
    }
}
