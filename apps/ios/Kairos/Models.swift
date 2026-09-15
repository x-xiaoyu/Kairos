import Foundation
import SwiftData

enum TimeBiasCalibrationChoice: String, Codable, CaseIterable {
    case automatic
    case accepted
    case declined
}

enum TaskStatus: String, Codable, CaseIterable { case todo, inProgress, complete }
enum CognitiveLoad: String, Codable, CaseIterable {
    case low, medium, high
    var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
enum DeadlineType: String, Codable, CaseIterable {
    case hard, soft, none
    var displayName: String {
        switch self {
        case .hard: "硬截止"
        case .soft: "软截止"
        case .none: "无截止"
        }
    }
}

enum TaskPlace: String, Codable, CaseIterable {
    case anywhere, home, outing
    var displayName: String {
        switch self {
        case .anywhere: "随地"
        case .home: "在家"
        case .outing: "出门"
        }
    }
    var icon: String {
        switch self {
        case .anywhere: "sparkles"
        case .home: "house.fill"
        case .outing: "figure.walk"
        }
    }
}

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
    var scheduledStart: Date? = nil
    /// Zero follows the normal priority/deadline order. Positive values are used
    /// only to place a postponed task later among tasks on the same calendar day.
    var dayOrder: Int = 0
    var isPrimaryCountdown: Bool = false
    var timeBiasCalibrationRaw: String = TimeBiasCalibrationChoice.automatic.rawValue
    var repeatsDaily: Bool = false
    var repeatHour: Int = 7
    var repeatMinute: Int = 0
    var linkedRoutineID: UUID? = nil
    var placeRaw: String = TaskPlace.anywhere.rawValue

    init(title: String, goal: String = "", deadline: Date? = nil, scheduledStart: Date? = nil, estimatedMinutes: Int = 30, priority: Int = 3, status: TaskStatus = .todo, cognitiveLoad: CognitiveLoad = .medium, isInterruptible: Bool = true, deadlineType: DeadlineType = .soft, isPrimaryCountdown: Bool = false, repeatsDaily: Bool = false, repeatHour: Int = 7, repeatMinute: Int = 0, linkedRoutineID: UUID? = nil, place: TaskPlace = .anywhere) {
        id = UUID(); self.title = title; self.goal = goal; self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes; self.priority = priority; statusRaw = status.rawValue
        cognitiveLoadRaw = cognitiveLoad.rawValue; self.isInterruptible = isInterruptible
        deadlineTypeRaw = deadlineType.rawValue; createdAt = .now; availableAfter = nil; self.scheduledStart = scheduledStart; dayOrder = 0; self.isPrimaryCountdown = isPrimaryCountdown
        timeBiasCalibrationRaw = TimeBiasCalibrationChoice.automatic.rawValue
        self.repeatsDaily = repeatsDaily
        self.repeatHour = repeatHour
        self.repeatMinute = repeatMinute
        self.linkedRoutineID = linkedRoutineID
        self.placeRaw = place.rawValue
    }

    func duplicatedAsTodo(scheduledStart: Date? = nil, keepRepeat: Bool = true) -> KairosTask {
        let copy = KairosTask(
            title: title,
            goal: goal,
            deadline: nil,
            scheduledStart: scheduledStart,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            status: .todo,
            cognitiveLoad: cognitiveLoad,
            isInterruptible: isInterruptible,
            deadlineType: .none,
            isPrimaryCountdown: false,
            repeatsDaily: keepRepeat && repeatsDaily,
            repeatHour: repeatHour,
            repeatMinute: repeatMinute,
            linkedRoutineID: keepRepeat ? linkedRoutineID : nil,
            place: place
        )
        copy.timeBiasCalibration = timeBiasCalibration
        return copy
    }

    var status: TaskStatus { get { TaskStatus(rawValue: statusRaw) ?? .todo } set { statusRaw = newValue.rawValue } }
    var cognitiveLoad: CognitiveLoad { get { CognitiveLoad(rawValue: cognitiveLoadRaw) ?? .medium } set { cognitiveLoadRaw = newValue.rawValue } }
    var deadlineType: DeadlineType { get { DeadlineType(rawValue: deadlineTypeRaw) ?? .soft } set { deadlineTypeRaw = newValue.rawValue } }
    var place: TaskPlace {
        get { TaskPlace(rawValue: placeRaw) ?? .anywhere }
        set { placeRaw = newValue.rawValue }
    }
    var timeBiasCalibration: TimeBiasCalibrationChoice {
        get { TimeBiasCalibrationChoice(rawValue: timeBiasCalibrationRaw) ?? .automatic }
        set { timeBiasCalibrationRaw = newValue.rawValue }
    }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetMinutes: Int
    var streak: Int = 0
    var bestStreak: Int = 0
    var lastCompletedDay: Date?
    init(title: String, targetMinutes: Int, streak: Int = 0, bestStreak: Int = 0) {
        id = UUID()
        self.title = title
        self.targetMinutes = targetMinutes
        self.streak = streak
        self.bestStreak = max(bestStreak, streak)
    }
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
