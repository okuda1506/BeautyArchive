import Foundation

private final class MemoryCloud: ReminderTimingCloudStorage {
    var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
    func synchronize() -> Bool { true }
}

private enum CheckFailure: Error {
    case expectation(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.expectation(message) }
}

@main
private enum ReminderTimingContract {
    @MainActor
    static func main() throws {
        let deviceA = ReminderTimingSnapshot(
            leadChoice: 7, customLeadDays: 2, revision: 2, deviceID: "device-A"
        )
        let deviceB = ReminderTimingSnapshot(
            leadChoice: 3, customLeadDays: 2, revision: 3, deviceID: "device-B"
        )
        try require(deviceB.isNewer(than: deviceA), "Later revision must win")
        try require(!deviceA.isNewer(than: deviceB), "Older revision must not win")
        let simultaneous = ReminderTimingSnapshot(
            leadChoice: 1, customLeadDays: 2, revision: 2, deviceID: "device-B"
        )
        try require(simultaneous.isNewer(than: deviceA), "Concurrent edits need a stable winner")
        try require(!deviceA.isNewer(than: simultaneous), "Concurrent order must be symmetric")
        let invalid = ReminderTimingSnapshot(
            leadChoice: 99, customLeadDays: 2, revision: 4, deviceID: "device-C"
        )
        try require(!invalid.isValid, "Invalid cloud choices must be ignored")

        let suite = "BONE-ReminderTiming-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw CheckFailure.expectation("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(7, forKey: ReminderPreferences.leadChoiceKey)
        defaults.set(5, forKey: ReminderPreferences.customLeadDaysKey)
        let migrated = ReminderTimingSettings(syncEnabled: false, defaults: defaults)
        try require(migrated.leadChoice == 7 && migrated.customLeadDays == 5,
                    "Existing local choices must survive migration")
        migrated.setCustomLeadDays(12)
        let reopened = ReminderTimingSettings(syncEnabled: false, defaults: defaults)
        try require(reopened.leadChoice == 7 && reopened.customLeadDays == 12,
                    "Changes must remain available without iCloud")

        let cloud = MemoryCloud()
        let synced = ReminderTimingSettings(defaults: defaults, cloud: cloud)
        try require(cloud.values["reminders.timing.v1"] != nil,
                    "Existing local choices must seed an empty cloud store")
        let newerRemote = ReminderTimingSnapshot(
            leadChoice: 3, customLeadDays: 20, revision: 10, deviceID: "remote-device"
        )
        cloud.values["reminders.timing.v1"] = try JSONEncoder().encode(newerRemote)
        synced.refreshFromCloud()
        try require(synced.leadChoice == 3 && synced.customLeadDays == 20,
                    "Newer remote timing must reach the visible settings")
        synced.setLeadChoice(-1)
        let published = try JSONDecoder().decode(
            ReminderTimingSnapshot.self,
            from: cloud.values["reminders.timing.v1"] ?? Data()
        )
        try require(published.revision == 11 && published.leadChoice == -1
                    && published.customLeadDays == 20,
                    "Local edit must advance the revision and retain remote custom days")
        let unreadable = Data("future-format".utf8)
        cloud.values["reminders.timing.v1"] = unreadable
        synced.refreshFromCloud()
        try require(cloud.values["reminders.timing.v1"] == unreadable,
                    "Unreadable remote data must not be overwritten")
        try require(synced.leadChoice == -1,
                    "Unreadable remote data must not discard local preferences")
        print("Reminder timing migration and conflict checks passed")
    }
}
