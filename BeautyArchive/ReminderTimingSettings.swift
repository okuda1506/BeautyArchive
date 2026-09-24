import Foundation
import Observation

nonisolated protocol ReminderTimingCloudStorage {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ReminderTimingCloudStorage {}

@MainActor
@Observable
final class ReminderTimingSettings {
    private(set) var leadChoice: Int
    private(set) var customLeadDays: Int

    @ObservationIgnored private var snapshot: ReminderTimingSnapshot
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: any ReminderTimingCloudStorage
    @ObservationIgnored private let syncEnabled: Bool
    @ObservationIgnored private let deviceID: String

    private static let cloudKey = "reminders.timing.v1"
    private static let localSnapshotKey = "reminders.timingSnapshot.v1"
    private static let deviceIDKey = "reminders.timingDeviceID.v1"

    init(
        syncEnabled: Bool = true,
        defaults: UserDefaults = .standard,
        cloud: any ReminderTimingCloudStorage = NSUbiquitousKeyValueStore.default
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.syncEnabled = syncEnabled
        let deviceID = defaults.string(forKey: Self.deviceIDKey) ?? UUID().uuidString
        self.deviceID = deviceID
        defaults.set(deviceID, forKey: Self.deviceIDKey)

        let saved = defaults.data(forKey: Self.localSnapshotKey)
            .flatMap { try? JSONDecoder().decode(ReminderTimingSnapshot.self, from: $0) }
        if let saved, saved.isValid {
            snapshot = saved
        } else {
            let oldChoice = defaults.object(forKey: ReminderPreferences.leadChoiceKey) as? Int
            let oldDays = defaults.object(forKey: ReminderPreferences.customLeadDaysKey) as? Int
            snapshot = ReminderTimingSnapshot(
                leadChoice: [-1, 0, 1, 3, 7].contains(oldChoice ?? 0) ? oldChoice ?? 0 : 0,
                customLeadDays: min(max(oldDays ?? 2, 0), 365),
                revision: oldChoice != nil || oldDays != nil ? 1 : 0,
                deviceID: deviceID
            )
        }
        leadChoice = snapshot.leadChoice
        customLeadDays = snapshot.customLeadDays
        if syncEnabled {
            cloud.synchronize()
            refreshFromCloud()
        }
    }

    func setLeadChoice(_ choice: Int) {
        guard [-1, 0, 1, 3, 7].contains(choice), choice != leadChoice else { return }
        refreshFromCloud()
        saveLocalChange(choice: choice, days: customLeadDays)
    }

    func setCustomLeadDays(_ days: Int) {
        guard (0...365).contains(days), days != customLeadDays else { return }
        refreshFromCloud()
        saveLocalChange(choice: leadChoice, days: days)
    }

    func refreshFromCloud() {
        guard syncEnabled else { return }
        guard let remoteData = cloud.data(forKey: Self.cloudKey) else {
            if snapshot.revision > 0 { publish(snapshot) }
            return
        }
        guard let remote = try? JSONDecoder().decode(ReminderTimingSnapshot.self, from: remoteData),
              remote.isValid else { return }
        if remote.isNewer(than: snapshot) {
            apply(remote)
        } else if snapshot.isNewer(than: remote) {
            publish(snapshot)
        }
    }

    private func saveLocalChange(choice: Int, days: Int) {
        guard choice != leadChoice || days != customLeadDays else { return }
        let next = ReminderTimingSnapshot(
            leadChoice: choice,
            customLeadDays: days,
            revision: snapshot.revision + 1,
            deviceID: deviceID
        )
        apply(next)
        if syncEnabled { publish(next) }
    }

    private func apply(_ value: ReminderTimingSnapshot) {
        snapshot = value
        leadChoice = value.leadChoice
        customLeadDays = value.customLeadDays
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.localSnapshotKey)
        }
        // Keep the former local keys for existing installs and data exports.
        defaults.set(value.leadChoice, forKey: ReminderPreferences.leadChoiceKey)
        defaults.set(value.customLeadDays, forKey: ReminderPreferences.customLeadDaysKey)
    }

    private func publish(_ value: ReminderTimingSnapshot) {
        if let data = try? JSONEncoder().encode(value) {
            cloud.set(data, forKey: Self.cloudKey)
        }
    }
}
