import Foundation

enum RiskLevel: String { case safe, warning, high, critical }

struct PlannedTask: Identifiable {
    let task: KairosTask
    let start: Date
    let end: Date
    let latestSafeStart: Date?
    let risk: RiskLevel
    var id: UUID { task.id }
}

enum Planner {
    static func latestSafeStart(for task: KairosTask, among tasks: [KairosTask], adjustment: Double = 1) -> Date? {
        guard let deadline = task.deadline, task.deadlineType != .none else { return nil }
        let competing = tasks.filter { other in
            other.id != task.id && other.status != .complete && other.deadline.map { $0 <= deadline } == true &&
            (other.priority > task.priority || (other.deadline ?? .distantFuture) < deadline)
        }.reduce(0) { $0 + Int(Double($1.estimatedMinutes) * adjustment) }
        let buffer = task.deadlineType == .hard ? 15 : 5
        return Calendar.current.date(byAdding: .minute, value: -(Int(Double(task.estimatedMinutes) * adjustment) + competing + buffer), to: deadline)
    }

    static func risk(now: Date, latestStart: Date?, estimatedMinutes: Int) -> RiskLevel {
        guard let latestStart else { return .safe }
        let minutes = latestStart.timeIntervalSince(now) / 60
        if minutes <= 0 { return .critical }
        if minutes <= Double(max(30, estimatedMinutes / 2)) { return .high }
        if minutes <= Double(max(90, estimatedMinutes * 3 / 2)) { return .warning }
        return .safe
    }

    static func makePlan(tasks: [KairosTask], now: Date = .now, adjustment: Double = 1) -> [PlannedTask] {
        let active = tasks.filter { $0.status != .complete }.sorted {
            let leftDeadline = $0.deadline ?? .distantFuture
            let rightDeadline = $1.deadline ?? .distantFuture
            if leftDeadline != rightDeadline { return leftDeadline < rightDeadline }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.createdAt < $1.createdAt
        }
        var cursor = now
        return active.map { task in
            if let availableAfter = task.availableAfter, availableAfter > cursor { cursor = availableAfter }
            let minutes = max(5, Int(Double(task.estimatedMinutes) * adjustment))
            let end = Calendar.current.date(byAdding: .minute, value: minutes, to: cursor)!
            let latest = latestSafeStart(for: task, among: active, adjustment: adjustment)
            let item = PlannedTask(task: task, start: cursor, end: end, latestSafeStart: latest, risk: risk(now: now, latestStart: latest, estimatedMinutes: minutes))
            cursor = Calendar.current.date(byAdding: .minute, value: 5, to: end)!
            return item
        }
    }
}
