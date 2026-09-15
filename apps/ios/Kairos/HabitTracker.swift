import Foundation
import SwiftData

enum HabitTracker {
    static func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = min(23, max(0, hour))
        components.minute = min(59, max(0, minute))
        components.second = 0
        let today = calendar.date(from: components) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    static func applyingRepeatTime(_ date: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = min(23, max(0, hour))
        components.minute = min(59, max(0, minute))
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    static func daysSinceLastCheckIn(_ lastCompletedDay: Date?, now: Date, calendar: Calendar = .current) -> Int? {
        guard let lastCompletedDay else { return nil }
        let last = calendar.startOfDay(for: lastCompletedDay)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: last, to: today).day
    }

    static func streakAfterMissedDays(currentStreak: Int, lastCompletedDay: Date?, now: Date, calendar: Calendar = .current) -> Int {
        guard let gap = daysSinceLastCheckIn(lastCompletedDay, now: now, calendar: calendar) else { return currentStreak }
        return gap >= 2 ? 0 : currentStreak
    }

    static func streakAfterCheckIn(currentStreak: Int, lastCompletedDay: Date?, now: Date, calendar: Calendar = .current) -> Int {
        let restored = streakAfterMissedDays(currentStreak: currentStreak, lastCompletedDay: lastCompletedDay, now: now, calendar: calendar)
        if let gap = daysSinceLastCheckIn(lastCompletedDay, now: now, calendar: calendar) {
            if gap == 0 { return restored }
            if gap == 1 { return restored + 1 }
        }
        return 1
    }

    static func bestStreak(currentBest: Int, newStreak: Int) -> Int {
        max(currentBest, newStreak)
    }

    static func applyMissedDayReset(_ routine: Routine, now: Date = .now, calendar: Calendar = .current) {
        routine.streak = streakAfterMissedDays(currentStreak: routine.streak, lastCompletedDay: routine.lastCompletedDay, now: now, calendar: calendar)
    }

    static func refreshBrokenStreaks(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        for routine in routines {
            applyMissedDayReset(routine, now: now, calendar: calendar)
        }
    }

    static func recordCheckIn(_ routine: Routine, now: Date = .now, calendar: Calendar = .current) {
        let next = streakAfterCheckIn(currentStreak: routine.streak, lastCompletedDay: routine.lastCompletedDay, now: now, calendar: calendar)
        if let gap = daysSinceLastCheckIn(routine.lastCompletedDay, now: now, calendar: calendar), gap == 0 {
            routine.bestStreak = bestStreak(currentBest: routine.bestStreak, newStreak: routine.streak)
            return
        }
        routine.streak = next
        routine.lastCompletedDay = now
        routine.bestStreak = bestStreak(currentBest: routine.bestStreak, newStreak: next)
    }

    @discardableResult
    static func ensureRoutine(for task: KairosTask, in context: ModelContext) -> Routine? {
        guard task.repeatsDaily else { return nil }
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        if let id = task.linkedRoutineID, let match = routines.first(where: { $0.id == id }) {
            match.title = task.title
            match.targetMinutes = task.estimatedMinutes
            return match
        }
        if let match = routines.first(where: { $0.title.compare(task.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            task.linkedRoutineID = match.id
            match.targetMinutes = task.estimatedMinutes
            return match
        }
        let routine = Routine(title: task.title, targetMinutes: task.estimatedMinutes)
        context.insert(routine)
        task.linkedRoutineID = routine.id
        return routine
    }

    static func handleCompletion(_ task: KairosTask, in context: ModelContext, existingTasks: [KairosTask], now: Date = .now, calendar: Calendar = .current) {
        refreshBrokenStreaks(in: context, now: now, calendar: calendar)
        guard task.repeatsDaily else { return }
        if let routine = ensureRoutine(for: task, in: context) {
            recordCheckIn(routine, now: now, calendar: calendar)
            context.insert(ActivityEvent(action: "Routine completed", taskTitle: routine.title, detail: "\(routine.streak) day streak protected. Best \(routine.bestStreak)."))
        }
        spawnNextIfNeeded(from: task, existing: existingTasks, in: context, now: now, calendar: calendar)
    }

    static func spawnNextIfNeeded(from task: KairosTask, existing: [KairosTask], in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard task.repeatsDaily else { return }
        let reference = max(now, task.scheduledStart ?? now)
        let nextStart = nextOccurrence(hour: task.repeatHour, minute: task.repeatMinute, after: reference, calendar: calendar)
        let alreadyQueued = existing.contains { candidate in
            candidate.id != task.id
                && candidate.status != .complete
                && candidate.repeatsDaily
                && sameHabit(candidate, task)
                && candidate.scheduledStart.map { calendar.isDate($0, inSameDayAs: nextStart) } == true
        }
        guard !alreadyQueued else { return }
        let copy = task.duplicatedAsTodo(scheduledStart: nextStart, keepRepeat: true)
        context.insert(copy)
        context.insert(ActivityEvent(action: "Task created", taskTitle: copy.title, detail: "Next repeating occurrence scheduled."))
    }

    private static func sameHabit(_ lhs: KairosTask, _ rhs: KairosTask) -> Bool {
        if let left = lhs.linkedRoutineID, let right = rhs.linkedRoutineID { return left == right }
        return lhs.title.compare(rhs.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
