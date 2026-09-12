import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable { case todo, inProgress, complete }
enum CognitiveLoad: String, Codable, CaseIterable { case low, medium, high }
enum DeadlineType: String, Codable, CaseIterable { case hard, soft, none }

@Model
final class KairosTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var goal: String
    var deadline: Date?
    var estimatedMinutes: Int
    var priority: Int
    var statusRaw: String
    var cognitiveLoadRaw: String
    var isInterruptible: Bool
    var deadlineTypeRaw: String
    var createdAt: Date
    var availableAfter: Date?

    init(title: String, goal: String = "", deadline: Date? = nil, estimatedMinutes: Int = 30, priority: Int = 3, status: TaskStatus = .todo, cognitiveLoad: CognitiveLoad = .medium, isInterruptible: Bool = true, deadlineType: DeadlineType = .soft) {
        id = UUID(); self.title = title; self.goal = goal; self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes; self.priority = priority; statusRaw = status.rawValue
        cognitiveLoadRaw = cognitiveLoad.rawValue; self.isInterruptible = isInterruptible
        deadlineTypeRaw = deadlineType.rawValue; createdAt = .now; availableAfter = nil
    }

    var status: TaskStatus { get { TaskStatus(rawValue: statusRaw) ?? .todo } set { statusRaw = newValue.rawValue } }
    var cognitiveLoad: CognitiveLoad { get { CognitiveLoad(rawValue: cognitiveLoadRaw) ?? .medium } set { cognitiveLoadRaw = newValue.rawValue } }
    var deadlineType: DeadlineType { get { DeadlineType(rawValue: deadlineTypeRaw) ?? .soft } set { deadlineTypeRaw = newValue.rawValue } }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetMinutes: Int
    var streak: Int
    var lastCompletedDay: Date?
    init(title: String, targetMinutes: Int, streak: Int = 0) { id = UUID(); self.title = title; self.targetMinutes = targetMinutes; self.streak = streak }
    var isDoneToday: Bool { guard let lastCompletedDay else { return false }; return Calendar.current.isDateInToday(lastCompletedDay) }
}

@Model
final class ActivityEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var action: String
    var taskTitle: String
    var detail: String
    init(action: String, taskTitle: String, detail: String, timestamp: Date = .now) { id = UUID(); self.timestamp = timestamp; self.action = action; self.taskTitle = taskTitle; self.detail = detail }
}

@Model
final class Workstyle {
    var wakeHour: Int
    var sleepHour: Int
    var focusBlockMinutes: Int
    var peakStartHour: Int
    var peakEndHour: Int
    var estimateAdjustment: Double
    init(wakeHour: Int = 7, sleepHour: Int = 23, focusBlockMinutes: Int = 45, peakStartHour: Int = 9, peakEndHour: Int = 12, estimateAdjustment: Double = 1) {
        self.wakeHour = wakeHour; self.sleepHour = sleepHour; self.focusBlockMinutes = focusBlockMinutes
        self.peakStartHour = peakStartHour; self.peakEndHour = peakEndHour; self.estimateAdjustment = estimateAdjustment
    }
}
