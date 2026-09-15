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
        if let scheduledStart = item.task.scheduledStart, scheduledStart > .now {
            await addNotification(
                id: "task-start-\(item.task.id)",
                at: scheduledStart,
                title: "该做这项任务了",
                body: "现在开始“\(item.task.title)”。",
                taskID: item.task.id
            )
        }
        if item.task.scheduledStart == nil, let start = item.latestSafeStart, start > .now {
            await addNotification(
                id: "latest-safe-\(item.task.id)",
                at: start,
                title: "该开始了",
                body: "现在开始“\(item.task.title)”，还能保住后面的安排。",
                taskID: item.task.id
            )
        }
        guard let deadline = item.task.deadline else { return }
        let reminders = [
            (suffix: "30", offset: -30 * 60, title: "只剩最后半小时", body: "“\(item.task.title)”即将截止，要现在开始吗？"),
            (suffix: "10", offset: -10 * 60, title: "只剩最后 10 分钟", body: "“\(item.task.title)”马上截止，请完成最重要的一步。"),
            (suffix: "due", offset: 0, title: "任务已经到期", body: "“\(item.task.title)”已到截止时间。现在开始仍然比继续推迟更好。")
        ]
        for reminder in reminders {
            let fireDate = deadline.addingTimeInterval(TimeInterval(reminder.offset))
            guard fireDate > .now else { continue }
            await addNotification(id: "deadline-\(reminder.suffix)-\(item.task.id)", at: fireDate, title: reminder.title, body: reminder.body, taskID: item.task.id)
        }
    }

    func reschedule(plan: [PlannedTask]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let kairosIDs = pending.map(\.identifier).filter { $0.hasPrefix("task-start-") || $0.hasPrefix("latest-safe-") || $0.hasPrefix("deadline-") }
        center.removePendingNotificationRequests(withIdentifiers: kairosIDs)
        for item in plan.prefix(12) { await schedule(for: item) }
    }

    private func addNotification(id: String, at date: Date, title: String, body: String, taskID: UUID) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["taskID": taskID.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    func clearStartReminder(for taskID: UUID) {
        let center = UNUserNotificationCenter.current()
        let identifier = "task-start-\(taskID)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
