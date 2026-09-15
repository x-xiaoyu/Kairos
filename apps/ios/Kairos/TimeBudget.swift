import Foundation

struct TimeBudgetSnapshot {
    let remainingMinutes: Int
    let neededMinutes: Int
    let taskCount: Int
    let horizon: Date
    let pick: PlannedTask?
    let isShort: Bool

    var confirmToken: String {
        "\(pick?.task.id.uuidString ?? "none")-\(taskCount)-\(neededMinutes)-\(isShort)"
    }
}

enum TimeBudget {
    static func evaluate(
        plan: [PlannedTask],
        now: Date = .now,
        presence: PlacePresence = .unknown,
        calendar: Calendar = .current
    ) -> TimeBudgetSnapshot {
        let today = plan.filter {
            calendar.isDate(Planner.scheduledDay(for: $0.task, now: now, calendar: calendar), inSameDayAs: now)
        }
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        let todayDeadlines = today.compactMap(\.task.deadline).filter { calendar.isDate($0, inSameDayAs: now) }
        // The total budget runs through the last deadline that still belongs to
        // today's queue. An earlier deadline affects ranking, but must not erase
        // the time available for tasks legitimately due later today.
        let horizon = todayDeadlines.max().map { min($0, endOfDay) } ?? endOfDay
        let remainingMinutes = max(0, Int(horizon.timeIntervalSince(now) / 60))
        let neededMinutes = today.reduce(0) {
            $0 + max(0, Int($1.end.timeIntervalSince($1.start) / 60))
        }
        let isShort = today.count >= 2 && neededMinutes >= max(1, remainingMinutes)
        let pick: PlannedTask?
        if isShort {
            pick = pickMostImportant(in: today, remainingMinutes: remainingMinutes, presence: presence)
        } else {
            pick = PlaceContext.suggestedStart(in: plan, presence: presence) ?? plan.first
        }
        return TimeBudgetSnapshot(
            remainingMinutes: remainingMinutes,
            neededMinutes: neededMinutes,
            taskCount: today.count,
            horizon: horizon,
            pick: pick,
            isShort: isShort
        )
    }

    static func remainingTimeText(minutes: Int) -> String {
        if minutes >= 24 * 60 { return "\(max(1, minutes / (24 * 60))) 天" }
        if minutes >= 60 {
            let hours = minutes / 60
            let leftover = minutes % 60
            if leftover == 0 { return "\(hours) 小时" }
            return "\(hours) 小时 \(leftover) 分钟"
        }
        return "\(minutes) 分钟"
    }

    private static func pickMostImportant(in items: [PlannedTask], remainingMinutes: Int, presence: PlacePresence) -> PlannedTask? {
        let ranked = items.enumerated().sorted { lhs, rhs in
            if let order = importanceOrder(lhs.element, rhs.element, presence: presence) {
                return order
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        guard let top = ranked.first else { return nil }
        if top.task.estimatedMinutes <= remainingMinutes || remainingMinutes == 0 {
            return top
        }
        return ranked.first(where: { $0.task.estimatedMinutes <= remainingMinutes }) ?? top
    }

    private static func importanceOrder(_ lhs: PlannedTask, _ rhs: PlannedTask, presence: PlacePresence) -> Bool? {
        let leftDeadlineKind = deadlineKindRank(lhs.task)
        let rightDeadlineKind = deadlineKindRank(rhs.task)
        if leftDeadlineKind != rightDeadlineKind { return leftDeadlineKind < rightDeadlineKind }

        let leftDue = lhs.task.deadline ?? .distantFuture
        let rightDue = rhs.task.deadline ?? .distantFuture
        if leftDue != rightDue { return leftDue < rightDue }

        if lhs.task.priority != rhs.task.priority { return lhs.task.priority > rhs.task.priority }

        if presence == .atHome {
            let leftLoad = loadRank(lhs.task.cognitiveLoad)
            let rightLoad = loadRank(rhs.task.cognitiveLoad)
            if leftLoad != rightLoad { return leftLoad > rightLoad }
        }

        let leftDoable = isActionableNow(lhs, presence: presence)
        let rightDoable = isActionableNow(rhs, presence: presence)
        if leftDoable != rightDoable { return leftDoable }
        return nil
    }

    private static func isActionableNow(_ item: PlannedTask, presence: PlacePresence) -> Bool {
        PlaceContext.isPinnedByUrgency(item.risk) || PlaceContext.isDoableNow(item.task.place, presence: presence)
    }

    private static func deadlineKindRank(_ task: KairosTask) -> Int {
        switch task.deadlineType {
        case .hard: 0
        case .soft: task.deadline == nil ? 2 : 1
        case .none: 2
        }
    }

    private static func loadRank(_ load: CognitiveLoad) -> Int {
        switch load {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}
