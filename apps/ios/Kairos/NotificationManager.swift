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
            let startNudge = KairosAdvisor.generateLocalNudge(for: item.task, stage: .start)
            await addNotification(
                id: "task-start-\(item.task.id)",
                at: scheduledStart,
                nudge: startNudge,
                task: item.task
            )
            if item.task.cognitiveLoad == .high {
                let transitionAt = scheduledStart.addingTimeInterval(-10 * 60)
                if transitionAt > .now {
                    let transitionNudge = KairosAdvisor.generateLocalNudge(for: item.task, stage: .transition)
                    await addNotification(
                        id: "task-transition-\(item.task.id)",
                        at: transitionAt,
                        nudge: transitionNudge,
                        task: item.task
                    )
                }
            }
        }
        if item.task.scheduledStart == nil, let start = item.latestSafeStart, start > .now {
            let rescue = KairosAdvisor.generateLocalNudge(for: item.task, stage: .graceRescue)
            await addNotification(
                id: "latest-safe-\(item.task.id)",
                at: start,
                nudge: rescue,
                task: item.task
            )
        }
        guard let deadline = item.task.deadline else { return }
        let rescue = KairosAdvisor.generateLocalNudge(for: item.task, stage: .graceRescue)
        let reminders = [
            (suffix: "30", offset: -30 * 60),
            (suffix: "10", offset: -10 * 60),
            (suffix: "due", offset: 0)
        ]
        for reminder in reminders {
            let fireDate = deadline.addingTimeInterval(TimeInterval(reminder.offset))
            guard fireDate > .now else { continue }
            await addNotification(
                id: "deadline-\(reminder.suffix)-\(item.task.id)",
                at: fireDate,
                nudge: rescue,
                task: item.task
            )
        }
    }

    func reschedule(plan: [PlannedTask]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let kairosIDs = pending.map(\.identifier).filter {
            $0.hasPrefix("task-start-") || $0.hasPrefix("task-transition-") || $0.hasPrefix("latest-safe-") || $0.hasPrefix("deadline-")
        }
        center.removePendingNotificationRequests(withIdentifiers: kairosIDs)
        for item in plan.prefix(12) { await schedule(for: item) }
    }

    private func addNotification(id: String, at date: Date, nudge: KairosAgentNudge, task: KairosTask) async {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.subtitle = nudge.subtitle
        content.body = "“\(task.title)” · \(nudge.composedMicroStep)"
        content.sound = nudge.stage == .transition ? nil : .default
        content.interruptionLevel = nudge.stage == .transition ? .active : .timeSensitive
        content.userInfo = [
            "taskID": task.id.uuidString,
            "nudgeStage": nudge.stage.rawValue
        ]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    func clearStartReminder(for taskID: UUID) {
        let center = UNUserNotificationCenter.current()
        let identifiers = ["task-start-\(taskID)", "task-transition-\(taskID)"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
