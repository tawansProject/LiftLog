import Foundation
import UserNotifications

/// Local notifications for rest timers. One pending rest notification at a time.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let restID = "rest-timer"

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleRestEnd(at date: Date, betweenExercises: Bool, nextUp: String?) {
        cancelRest()
        guard AppSettings.restNotifications else { return }
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = betweenExercises ? "Rest over: next exercise" : "Rest over: next set"
        if let nextUp { content.body = nextUp }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: content, trigger: trigger))
    }

    func cancelRest() {
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        center.removeDeliveredNotifications(withIdentifiers: [restID])
    }

    // Show the banner even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
