import UIKit
import UserNotifications

final class ReminderNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Normal foreground launches can still report .background here.
        // Consume background notification launches when their action arrives.
        let center = UNUserNotificationCenter.current()
        // Install before launch finishes, including launches caused by a Watch action.
        // UIApplicationDelegateAdaptor retains this object; the center's delegate is weak.
        center.delegate = self
        let actions = [ReminderNotificationAction.tomorrow, .nextWeek].map {
            UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
        }
        let categories = [ReminderNotificationTarget.Kind.product, .salon].map {
            UNNotificationCategory(identifier: $0.rawValue, actions: actions,
                                   intentIdentifiers: [], options: [])
        }
        center.setNotificationCategories(Set(categories))
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        if ReminderNotificationAction(rawValue: response.actionIdentifier) != nil {
            await LaunchPresentation.shared.finish()
        }
        let input = ReminderNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: request.identifier,
            categoryIdentifier: request.content.categoryIdentifier,
            userInfo: request.content.userInfo as? [String: String] ?? [:]
        )
        // No .foreground option: mirrored Watch actions execute on the paired iPhone.
        await ReminderNotificationCoordinator.shared.handle(input)
    }
}
