import Foundation

enum KairosAgentAction: Equatable {
    case createTask
    case postpone
    case changeDuration
    case changePriority
    case complete
    case replan
    case none
}

struct KairosAgentOperation: Equatable {
    let action: KairosAgentAction
    var taskID: UUID?
    var taskTitle: String?
    var value: Int?
    var deadline: Date?
    var isPrimaryCountdown = false
}

struct KairosAgentProposal: Identifiable, Equatable {
    let id = UUID()
    let action: KairosAgentAction
    let title: String
    let explanation: String
    var taskID: UUID?
    var taskTitle: String?
    var value: Int?
    var deadline: Date?
    var isPrimaryCountdown = false
    var requiresConfirmation: Bool
    var additionalOperations: [KairosAgentOperation] = []

    var operations: [KairosAgentOperation] {
        [KairosAgentOperation(action: action, taskID: taskID, taskTitle: taskTitle, value: value, deadline: deadline, isPrimaryCountdown: isPrimaryCountdown)] + additionalOperations
    }

    var isMultipleTaskCreation: Bool {
        operations.count > 1 && operations.allSatisfy { $0.action == .createTask }
    }

    func combinedTaskCreation() -> KairosAgentProposal {
        guard isMultipleTaskCreation else { return self }
        let totalMinutes = operations.reduce(0) { $0 + ($1.value ?? 30) }
        let firstTitle = operations.first?.taskTitle ?? taskTitle ?? "新任务"
        let combinedTitle = firstTitle.replacingOccurrences(of: #"\s*[（(]\d+/\d+[）)]$"#, with: "", options: .regularExpression)
        return KairosAgentProposal(
            action: .createTask,
            title: "把“\(combinedTitle)”作为一个任务加入计划？",
            explanation: explanation,
            taskTitle: combinedTitle,
            value: totalMinutes,
            deadline: deadline,
            isPrimaryCountdown: isPrimaryCountdown,
            requiresConfirmation: requiresConfirmation
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.action == rhs.action && lhs.title == rhs.title && lhs.taskID == rhs.taskID && lhs.value == rhs.value && lhs.additionalOperations == rhs.additionalOperations
    }
}

struct KairosRecommendation {
    let eyebrow: String
    let headline: String
    let reason: String
    let consequence: String
    let urgency: RiskLevel
}

enum KairosAdvisor {
    static func recommendation(for plan: [PlannedTask], now: Date = .now) -> KairosRecommendation? {
        guard let next = plan.first else { return nil }
        let safeBy = next.latestSafeStart?.formatted(date: .omitted, time: .shortened)
        let reason: String
        switch next.risk {
        case .critical: reason = "安全开始时间已经过去。现在开始，可以尽量保住今天剩余的安排。"
        case .high: reason = "已经接近最晚安全开始时间\(safeBy.map { "（\($0)）" } ?? "")。"
        case .warning: reason = "在 \(safeBy ?? "安全开始时间") 前开始，后面的安排仍有调整空间。"
        case .safe: reason = "综合优先级、截止时间和所需时长，这是现在最合适的一步。"
        }
        let consequence: String
        if plan.count > 1 {
            let later = plan[1].task.title
            consequence = "如果推迟 \(next.task.estimatedMinutes) 分钟，“\(later)”也会顺延。"
        } else if let deadline = next.task.deadline {
            let remaining = max(0, Int(deadline.timeIntervalSince(now) / 60))
            consequence = "距离截止时间约有 \(Self.remainingTimeText(minutes: remaining))；继续推迟会减少缓冲时间。"
        } else {
            consequence = "现在仍有调整空间，但立即开始可以保留稍后的自由时间。"
        }
        return KairosRecommendation(eyebrow: next.risk == .safe ? "KAIROS 建议" : "安全时间正在缩短", headline: "现在开始“\(next.task.title)”", reason: reason, consequence: consequence, urgency: next.risk)
    }

    private static func remainingTimeText(minutes: Int) -> String {
        if minutes >= 24 * 60 { return "\(max(1, minutes / (24 * 60))) 天" }
        if minutes >= 60 { return "\(max(1, minutes / 60)) 小时" }
        return "\(minutes) 分钟"
    }

    static func interpret(_ input: String, tasks: [KairosTask], now: Date = .now, countedTaskStyle: String = "split") -> KairosAgentProposal {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let active = tasks.filter { $0.status != .complete }
        let target = active.first { lower.contains($0.title.lowercased()) } ?? active.first
        let minutes = firstNumber(in: lower)
        let creationWords = ["添加", "新建", "记下", "我要", "我想", "想做", "安排", "提醒我", "加一个", "add", "create", "need to", "remind me to"]
        let taskCount = countedTaskCount(in: lower)
        let isCountedCreation = taskCount > 1 && ["刷", "做", "练", "solve", "finish"].contains(where: lower.contains)
        let isCreation = creationWords.contains(where: lower.contains) || isCountedCreation

        if lower.contains("累") || lower.contains("tired") || lower.contains("没状态") || lower.contains("low energy") {
            let lowLoad = active.filter { $0.cognitiveLoad == .low }.sorted { $0.priority > $1.priority }.first
            let suggestion = lowLoad?.title ?? target?.title ?? "先休息几分钟"
            return KairosAgentProposal(action: .replan, title: "切换到低能量计划", explanation: "没关系。根据你现在的状态，可以先做“\(suggestion)”，把高认知任务留到状态更好的时间。", taskID: lowLoad?.id, taskTitle: lowLoad?.title, requiresConfirmation: false)
        }

        if lower.contains("推迟") || lower.contains("延后") || lower.contains("postpone") || lower.contains("delay") {
            guard let target else { return noTaskProposal() }
            let value = max(5, minutes ?? 30)
            return KairosAgentProposal(action: .postpone, title: "将“\(target.title)”推迟 \(value) 分钟？", explanation: "Kairos 会把它推迟到 \(now.addingTimeInterval(Double(value * 60)).formatted(date: .omitted, time: .shortened))，并立即重新安排今天剩余的任务。", taskID: target.id, taskTitle: target.title, value: value, requiresConfirmation: true)
        }

        if isCreation {
            let providedDuration = durationMinutes(in: lower)
            let duration = min(720, max(5, providedDuration ?? 30))
            let cleaned = cleanTaskTitle(trimmed)
            let deadline = inferredDeadline(from: lower, now: now)
            let count = taskCount
            if count > 1 && countedTaskStyle != "combined" {
                let perTaskMinutes: Int
                if providedDuration == nil || lower.contains("每题") || lower.contains("每个") {
                    perTaskMinutes = duration
                } else {
                    perTaskMinutes = max(5, duration / count)
                }
                let baseTitle = removingCount(from: cleaned)
                let operations = (1...count).map {
                    KairosAgentOperation(action: .createTask, taskTitle: "\(baseTitle)（\($0)/\(count)）", value: perTaskMinutes, deadline: deadline)
                }
                let first = operations[0]
                return KairosAgentProposal(
                    action: first.action,
                    title: "已准备拆成 \(count) 条任务",
                    explanation: "默认安排在今天，每条约 \(perTaskMinutes) 分钟；确认后会按顺序加入，最新创建的排在同一时间任务的最后。",
                    taskTitle: first.taskTitle,
                    value: first.value,
                    deadline: first.deadline,
                    requiresConfirmation: true,
                    additionalOperations: Array(operations.dropFirst())
                )
            }
            return KairosAgentProposal(action: .createTask, title: "把“\(cleaned)”加入今天的计划？", explanation: "默认执行一次，预计需要 \(duration) 分钟，截止时间为 \(deadline.formatted(date: .abbreviated, time: .shortened))。确认后仍然可以编辑细节。", taskTitle: cleaned, value: duration, deadline: deadline, requiresConfirmation: true)
        }

        if lower.contains("时长") || lower.contains("分钟") || lower.contains("改成") || lower.contains("duration") || lower.contains("take") {
            if let target, let minutes {
                let value = min(720, max(5, minutes))
                return KairosAgentProposal(action: .changeDuration, title: "把“\(target.title)”改为 \(value) 分钟？", explanation: "Kairos 会修改预计时长，并重新计算它之后所有任务的安全开始时间。", taskID: target.id, taskTitle: target.title, value: value, requiresConfirmation: true)
            }
        }

        if lower.contains("完成") || lower.contains("done") || lower.contains("complete") {
            guard let target else { return noTaskProposal() }
            return KairosAgentProposal(action: .complete, title: "将“\(target.title)”标记为已完成？", explanation: "它会进入完成历史，Kairos 会把这段时间释放回今天的计划。", taskID: target.id, taskTitle: target.title, requiresConfirmation: true)
        }

        if lower.contains("重排") || lower.contains("重新安排") || lower.contains("replan") {
            return KairosAgentProposal(action: .replan, title: "今天的计划已重新计算", explanation: "Kairos 已根据最新的优先级、截止时间、任务时长和安全开始风险重新评估今天。", requiresConfirmation: false)
        }

        if active.isEmpty && !trimmed.isEmpty {
            let deadline = inferredDeadline(from: lower, now: now)
            return KairosAgentProposal(action: .createTask, title: "把“\(trimmed)”加入今天的计划？", explanation: "默认执行一次、预计 30 分钟。确认后仍然可以修改。", taskTitle: trimmed, value: 30, deadline: deadline, requiresConfirmation: true)
        }

        return KairosAgentProposal(action: .none, title: "我还没有理解这句话", explanation: "你可以说：“今晚添加刷两道 LeetCode，40 分钟”、“推迟 30 分钟”、“这个任务改成 20 分钟”或“我今天很累”。", requiresConfirmation: false)
    }

    private static func firstNumber(in text: String) -> Int? {
        if text.contains("半小时") { return 30 }
        if text.contains("两小时") || text.contains("两个小时") { return 120 }
        if text.contains("一小时") || text.contains("一个小时") { return 60 }
        guard let range = text.range(of: #"[0-9]+"#, options: .regularExpression) else { return nil }
        let number = Int(text[range])
        if text.contains("hour") || text.contains("小时") { return number.map { $0 * 60 } }
        return number
    }

    private static func durationMinutes(in text: String) -> Int? {
        if text.contains("半小时") { return 30 }
        let pattern = #"([0-9]+)\s*(分钟|min|minutes|小时|hours?)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let fragment = String(text[match])
        guard let numberRange = fragment.range(of: #"[0-9]+"#, options: .regularExpression), let number = Int(fragment[numberRange]) else { return nil }
        return fragment.contains("小时") || fragment.lowercased().contains("hour") ? number * 60 : number
    }

    private static func countedTaskCount(in text: String) -> Int {
        if let range = text.range(of: #"[0-9]+\s*(道|个)?\s*(题|questions?)"#, options: [.regularExpression, .caseInsensitive]),
           let numberRange = text[range].range(of: #"[0-9]+"#, options: .regularExpression),
           let count = Int(text[numberRange]) { return min(20, max(1, count)) }
        let chineseCounts = [("十", 10), ("九", 9), ("八", 8), ("七", 7), ("六", 6), ("五", 5), ("四", 4), ("三", 3), ("两", 2), ("二", 2)]
        return chineseCounts.first(where: { text.contains("\($0.0)道") || text.contains("\($0.0)个") })?.1 ?? 1
    }

    private static func removingCount(from title: String) -> String {
        title.replacingOccurrences(of: #"([0-9]+|二|两|三|四|五|六|七|八|九|十)\s*(道|个)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanTaskTitle(_ text: String) -> String {
        var result = text
        let removals = ["请帮我", "帮我", "添加", "新建", "记下", "我要", "我想", "想做", "需要", "安排", "提醒我", "加一个", "add", "create", "need to", "remind me to", "今天", "今晚", "明天"]
        for word in removals { result = result.replacingOccurrences(of: word, with: "", options: .caseInsensitive) }
        result = result.replacingOccurrences(of: #"(上午|下午|晚上)?\s*([0-2]?\d|一|二|两|三|四|五|六|七|八|九|十|十一|十二)\s*[点时](半|[0-5]?\d分?)?"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[,，]?\s*(半|一|一个|两|两个)小时.*$"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[,，]?\s*[0-9]+\s*(分钟|min|minutes|小时|hours?).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        result = result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return result.isEmpty ? "新任务" : result
    }

    private static func inferredDeadline(from text: String, now: Date) -> Date {
        let calendar = Calendar.current
        if let clock = clockTime(in: text) {
            let base = text.contains("明天") || text.contains("tomorrow") ? calendar.date(byAdding: .day, value: 1, to: now)! : now
            return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: base)!
        }
        if text.contains("今晚") || text.contains("tonight") { return calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now)! }
        if text.contains("明天") || text.contains("tomorrow") {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow)!
        }
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now)!
    }

    private static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        if let range = text.range(of: #"([01]?\d|2[0-3]):([0-5]\d)"#, options: .regularExpression) {
            let parts = text[range].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        let numbers = ["一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12]
        for (word, value) in numbers.sorted(by: { $0.key.count > $1.key.count }) where text.contains("\(word)点") {
            let evening = text.contains("晚") || text.contains("下午")
            return (evening && value < 12 ? value + 12 : value, text.contains("半") ? 30 : 0)
        }
        return nil
    }

    private static func noTaskProposal() -> KairosAgentProposal {
        KairosAgentProposal(action: .none, title: "目前没有待办任务", explanation: "先添加一个任务，之后我就能帮你推迟、修改时长、完成和重新安排。", requiresConfirmation: false)
    }
}
