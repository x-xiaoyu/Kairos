import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published var authorizationGranted = false

    func requestPermission() async {
        do { authorizationGranted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { authorizationGranted = false }
    }

    func schedule(for item: PlannedTask) async {
        guard let start = item.latestSafeStart, start > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "It’s time to start"
        content.body = "Begin \(item.task.title) now to keep the rest of your day workable."
        content.sound = .default
        content.userInfo = ["taskID": item.task.id.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        let request = UNNotificationRequest(identifier: "latest-safe-\(item.task.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    func reschedule(plan: [PlannedTask]) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = plan.map { "latest-safe-\($0.task.id)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for item in plan { await schedule(for: item) }
    }
}
