import Foundation

nonisolated struct ReminderTimingSnapshot: Codable, Equatable {
    let leadChoice: Int
    let customLeadDays: Int
    let revision: UInt64
    let deviceID: String

    var isValid: Bool {
        [-1, 0, 1, 3, 7].contains(leadChoice)
            && (0...365).contains(customLeadDays)
            && !deviceID.isEmpty
    }

    func isNewer(than other: Self) -> Bool {
        if revision != other.revision { return revision > other.revision }
        if deviceID != other.deviceID { return deviceID > other.deviceID }
        if leadChoice != other.leadChoice { return leadChoice > other.leadChoice }
        return customLeadDays > other.customLeadDays
    }
}
