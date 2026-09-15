import Foundation

enum RiskLevel: String {
    case safe, warning, high, critical
    var displayName: String {
        switch self {
        case .safe: "从容"
        case .warning: "留意"
        case .high: "紧迫"
        case .critical: "紧急"
        }
    }
}

struct PlannedTask: Identifiable {
    let task: KairosTask
    let start: Date
    let end: Date
    let latestSafeStart: Date?
    let risk: RiskLevel
    var id: UUID { task.id }
}

enum Planner {
    static func scheduledDay(for task: KairosTask, now: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: task.scheduledStart ?? task.deadline ?? now)
    }

    static func isScheduledOnSameDay(_ lhs: KairosTask, _ rhs: KairosTask, now: Date, calendar: Calendar = .current) -> Bool {
        scheduledDay(for: lhs, now: now, calendar: calendar) == scheduledDay(for: rhs, now: now, calendar: calendar)
    }

    static func postponeWithinDay(_ task: KairosTask, among tasks: [KairosTask], minutes _: Int, now: Date = .now, calendar: Calendar = .current) {
        let day = scheduledDay(for: task, now: now, calendar: calendar)
        var sameDay = tasks.filter {
            $0.status != .complete && scheduledDay(for: $0, now: now, calendar: calendar) == day
        }.sorted {
            isOrderedBefore($0, $1, now: now, calendar: calendar)
        }
        guard let currentIndex = sameDay.firstIndex(where: { $0.id == task.id }),
              sameDay.indices.contains(currentIndex + 1) else { return }

        sameDay.swapAt(currentIndex, currentIndex + 1)
        for (index, item) in sameDay.enumerated() {
            item.dayOrder = index + 1
        }
        task.availableAfter = nil
    }

    static func latestSafeStart(for task: KairosTask, among tasks: [KairosTask], adjustment: Double = 1, bias: TimeBiasProfile = .neutral, ignoreDecline: Bool = false) -> Date? {
        guard let deadline = task.deadline, task.deadlineType != .none else { return nil }
        let competing = tasks.filter { other in
            other.id != task.id && other.status != .complete && other.deadline.map { $0 <= deadline } == true &&
            (other.priority > task.priority || (other.deadline ?? .distantFuture) < deadline)
        }.reduce(0) { $0 + TimeBiasReflector.calibratedDuration(for: $1, bias: bias, baseAdjustment: adjustment, ignoreDecline: ignoreDecline) }
        let buffer = task.deadlineType == .hard ? 15 : 5
        let own = TimeBiasReflector.calibratedDuration(for: task, bias: bias, baseAdjustment: adjustment, ignoreDecline: ignoreDecline)
        return Calendar.current.date(byAdding: .minute, value: -(own + competing + buffer), to: deadline)
    }

    static func risk(now: Date, latestStart: Date?, estimatedMinutes: Int) -> RiskLevel {
        guard let latestStart else { return .safe }
        let minutes = latestStart.timeIntervalSince(now) / 60
        if minutes <= 0 { return .critical }
        if minutes <= Double(max(30, estimatedMinutes / 2)) { return .high }
        if minutes <= Double(max(90, estimatedMinutes * 3 / 2)) { return .warning }
        return .safe
    }

    static func makePlan(tasks: [KairosTask], now: Date = .now, adjustment: Double = 1, bias: TimeBiasProfile = .neutral) -> [PlannedTask] {
        let calendar = Calendar.current
        let active = tasks.filter { $0.status != .complete }.sorted {
            isOrderedBefore($0, $1, now: now, calendar: calendar)
        }
        var cursor = now
        var activeDay: Date?
        return active.map { task in
            let taskDay = scheduledDay(for: task, now: now, calendar: calendar)
            if taskDay != activeDay {
                activeDay = taskDay
                cursor = taskDay == calendar.startOfDay(for: now) ? now : taskDay
            }
            if let scheduledStart = task.scheduledStart, scheduledStart > cursor { cursor = scheduledStart }
            if let availableAfter = task.availableAfter, availableAfter > cursor { cursor = availableAfter }
            let minutes = TimeBiasReflector.calibratedDuration(for: task, bias: bias, baseAdjustment: adjustment)
            let end = Calendar.current.date(byAdding: .minute, value: minutes, to: cursor)!
            let latest = latestSafeStart(for: task, among: active, adjustment: adjustment, bias: bias)
            let ratio = bias.adjustment(for: task.cognitiveLoad)
            let declined = task.timeBiasCalibration == .declined
            let riskLatest = declined && ratio > TimeBiasReflector.underestimateThreshold
                ? latestSafeStart(for: task, among: active, adjustment: adjustment, bias: bias, ignoreDecline: true)
                : latest
            let riskMinutes = declined && ratio > TimeBiasReflector.underestimateThreshold
                ? TimeBiasReflector.calibratedDuration(for: task, bias: bias, baseAdjustment: adjustment, ignoreDecline: true)
                : minutes
            let item = PlannedTask(
                task: task,
                start: cursor,
                end: end,
                latestSafeStart: latest,
                risk: risk(now: now, latestStart: riskLatest, estimatedMinutes: riskMinutes)
            )
            cursor = Calendar.current.date(byAdding: .minute, value: 5, to: end)!
            return item
        }
    }

    private static func isOrderedBefore(_ lhs: KairosTask, _ rhs: KairosTask, now: Date, calendar: Calendar) -> Bool {
        let leftDay = scheduledDay(for: lhs, now: now, calendar: calendar)
        let rightDay = scheduledDay(for: rhs, now: now, calendar: calendar)
        if leftDay != rightDay { return leftDay < rightDay }
        if (lhs.dayOrder == 0) != (rhs.dayOrder == 0) { return lhs.dayOrder == 0 }
        if lhs.dayOrder != rhs.dayOrder { return lhs.dayOrder < rhs.dayOrder }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        let leftDeadline = lhs.deadline ?? .distantFuture
        let rightDeadline = rhs.deadline ?? .distantFuture
        if leftDeadline != rightDeadline { return leftDeadline < rightDeadline }
        return lhs.createdAt < rhs.createdAt
    }
}
