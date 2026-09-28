import Foundation

/// Notification scheduling is device-specific, just like notification permission.
/// Snoozing does not change the product estimate, salon due date, or CloudKit data.
@MainActor
final class ReminderNotificationSnoozeStore {
    struct Record: Equatable {
        let revision: String
        let fireDate: Date
    }

    static let shared = ReminderNotificationSnoozeStore()
    private static let storageKey = "reminders.notificationSnoozes.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var records: [String: [String: Any]] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: [String: Any]] ?? [:]
    }

    func record(for identifier: String) -> Record? {
        guard let value = records[identifier],
              let revision = value["revision"] as? String, !revision.isEmpty,
              let date = value["fireDate"] as? Date, date.timeIntervalSince1970.isFinite
        else { return nil }
        return Record(revision: revision, fireDate: date)
    }

    func set(_ record: Record?, for identifier: String) {
        var values = records
        if let record {
            values[identifier] = ["revision": record.revision, "fireDate": record.fireDate]
        } else {
            values.removeValue(forKey: identifier)
        }
        defaults.set(values, forKey: Self.storageKey)
    }

    func retain(targets: [ReminderNotificationTarget], enabled: Bool) {
        let revisions = Dictionary(targets.map { ($0.identifier, $0.revision) },
                                   uniquingKeysWith: { first, _ in first })
        let values = records.filter { identifier, _ in
            enabled && record(for: identifier)?.revision == revisions[identifier]
                && revisions[identifier] != nil
        }
        defaults.set(values, forKey: Self.storageKey)
    }
}
