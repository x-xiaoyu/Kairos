import Foundation

enum KairosAgentAction: Equatable {
    case createTask
    case postpone
    case changeDuration
    case changePriority
    case complete
    case replan
    case startFocus
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
    let confirmPrompt: String
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let urgency: RiskLevel
    let pickID: UUID?
    let isTimeShort: Bool
    let confirmToken: String
}

enum NudgeStage: String, Equatable, Sendable {
    /// 计划开始前 10–15 分钟的心理预热，尤其适合高认知负荷任务。
    case transition
    /// 到点启动：只给出一个毫不费力的最小物理动作。
    case start
    /// 临近 Latest Safe Start 或用户刚顺延：接纳卡壳，提供无压力降级。
    case graceRescue
}

enum NudgeSource: String, Equatable, Sendable {
    case local
    case model
}

struct KairosAgentNudge: Equatable, Sendable {
    let stage: NudgeStage
    let title: String
    let subtitle: String
    let body: String
    let microStep: String
    let microStepLabel: String
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let trialMinutes: Int
    let source: NudgeSource

    var composedMicroStep: String {
        "💡 \(microStepLabel)：\(microStep)"
    }

    var notificationBody: String {
        [body, composedMicroStep].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum KairosAdvisor {
    static func recommendation(for plan: [PlannedTask], presence: PlacePresence = .unknown, now: Date = .now, calendar: Calendar = .current) -> KairosRecommendation? {
        let budget = TimeBudget.evaluate(plan: plan, now: now, presence: presence, calendar: calendar)
        guard let next = budget.pick else { return nil }
        if budget.isShort {
            return timeShortRecommendation(pick: next, budget: budget)
        }
        let safeBy = next.latestSafeStart?.formatted(date: .omitted, time: .shortened)
        let placeNote: String?
        switch presence {
        case .atHome where next.task.place == .outing:
            placeNote = "虽然这件要出门，但已经很紧迫，不能因为人在家就先放下。"
        case .away where next.task.place == .home:
            placeNote = "虽然这件通常在家做，但已经很紧迫。"
        case .atHome:
            placeNote = plan.contains(where: { $0.task.place == .outing && !PlaceContext.isPinnedByUrgency($0.risk) })
                ? "出门类任务先放着；现在适合做在家就能完成的事。"
                : nil
        case .away:
            placeNote = plan.contains(where: { $0.task.place == .home && !PlaceContext.isPinnedByUrgency($0.risk) })
                ? "回家再做家务类任务；现在优先能在外面完成的。"
                : nil
        case .unknown:
            placeNote = nil
        }
        let reason: String
        switch next.risk {
        case .critical: reason = [placeNote, "安全开始时间已经过去。现在开始，可以尽量保住今天剩余的安排。"].compactMap { $0 }.joined(separator: " ")
        case .high: reason = [placeNote, "已经接近最晚安全开始时间\(safeBy.map { "（\($0)）" } ?? "")。"].compactMap { $0 }.joined(separator: " ")
        case .warning: reason = [placeNote, "在 \(safeBy ?? "安全开始时间") 前开始，后面的安排仍有调整空间。"].compactMap { $0 }.joined(separator: " ")
        case .safe: reason = [placeNote, "综合优先级、截止时间、所需时长和你现在的位置，这是现在最合适的一步。"].compactMap { $0 }.joined(separator: " ")
        }
        let consequence: String
        if let later = plan.first(where: { $0.id != next.id }) {
            consequence = "如果推迟 \(next.task.estimatedMinutes) 分钟，“\(later.task.title)”也会跟着受影响。"
        } else if let deadline = next.task.deadline {
            let remaining = max(0, Int(deadline.timeIntervalSince(now) / 60))
            consequence = "距离截止时间约有 \(TimeBudget.remainingTimeText(minutes: remaining))；继续推迟会减少缓冲时间。"
        } else {
            consequence = "现在仍有调整空间，但立即开始可以保留稍后的自由时间。"
        }
        let prefix = presence == .unknown ? "现在开始" : "\(presence.headline)，先做"
        return KairosRecommendation(
            eyebrow: next.risk == .safe ? "Kairos 建议" : "安全时间正在缩短",
            headline: "\(prefix)“\(next.task.title)”",
            reason: reason,
            consequence: consequence,
            confirmPrompt: "",
            primaryActionTitle: "开始当前任务",
            secondaryActionTitle: "顺延当前任务",
            urgency: next.risk,
            pickID: next.task.id,
            isTimeShort: false,
            confirmToken: budget.confirmToken
        )
    }

    private static func timeShortRecommendation(pick: PlannedTask, budget: TimeBudgetSnapshot) -> KairosRecommendation {
        let remaining = TimeBudget.remainingTimeText(minutes: budget.remainingMinutes)
        let needed = TimeBudget.remainingTimeText(minutes: budget.neededMinutes)
        let leftoverNote = pick.task.estimatedMinutes > budget.remainingMinutes && budget.remainingMinutes > 0
            ? "完整做完可能来不及，先开始最重要的这一项就好。"
            : "先保住最重要的一项，其余先放下，不代表失败。"
        return KairosRecommendation(
            eyebrow: "时间不够一次做完",
            headline: budget.remainingMinutes == 0
                ? "今天剩下的时间已经不够，建议先做“\(pick.task.title)”"
                : "剩下约 \(remaining)，建议先做“\(pick.task.title)”",
            reason: "今天还有 \(budget.taskCount) 项，大约需要 \(needed)。\(leftoverNote)",
            consequence: "同时催这 \(budget.taskCount) 项只会更乱。先确认要不要做这一项。",
            confirmPrompt: "要先做“\(pick.task.title)”吗？",
            primaryActionTitle: "先做“\(pick.task.title)”",
            secondaryActionTitle: "稍后再说",
            urgency: pick.risk == .safe ? .warning : pick.risk,
            pickID: pick.task.id,
            isTimeShort: true,
            confirmToken: budget.confirmToken
        )
    }

    static func refineRecommendation(_ recommendation: KairosRecommendation, pick: PlannedTask, budget: TimeBudgetSnapshot) async -> KairosRecommendation {
        guard recommendation.isTimeShort else { return recommendation }
        let mode = UserDefaults.standard.string(forKey: "agentMode") ?? "local"
        guard mode == "personal" else { return recommendation }
        do {
            return try await PersonalAIService().refineTimeShortRecommendation(recommendation, pick: pick, budget: budget)
        } catch {
            return recommendation
        }
    }

    static func generateLocalNudge(for task: KairosTask, stage: NudgeStage) -> KairosAgentNudge {
        NudgeEngine.localNudge(for: task, stage: stage)
    }

    static func resolveNudgeStage(for task: KairosTask, latestSafeStart: Date?, now: Date = .now) -> NudgeStage {
        if task.dayOrder > 0 { return .graceRescue }
        if let latest = latestSafeStart, latest.timeIntervalSince(now) <= 15 * 60 { return .graceRescue }
        if let start = task.scheduledStart, now < start { return .transition }
        return .start
    }

    /// 本地规则立即返回；若已连接个人大模型，再异步精炼。失败时静默回落到本地文案。
    static func generateNudge(for task: KairosTask, stage: NudgeStage) async -> KairosAgentNudge {
        let local = generateLocalNudge(for: task, stage: stage)
        let mode = UserDefaults.standard.string(forKey: "agentMode") ?? "local"
        guard mode == "personal" else { return local }
        do {
            return try await PersonalAIService().generateNudge(task: task, stage: stage, fallback: local)
        } catch {
            return local
        }
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

        if isPriorityQuestion(lower) {
            return priorityProposal(tasks: active, now: now)
        }

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

    private static func isPriorityQuestion(_ text: String) -> Bool {
        let keys = ["该做", "先做哪", "先做什么", "现在做什么", "来得及", "时间不够", "优先做", "哪个最重要", "what should i do", "which first"]
        return keys.contains(where: text.contains)
    }

    private static func priorityProposal(tasks: [KairosTask], now: Date) -> KairosAgentProposal {
        guard !tasks.isEmpty else { return noTaskProposal() }
        let plan = Planner.makePlan(tasks: tasks, now: now)
        let budget = TimeBudget.evaluate(plan: plan, now: now)
        guard let pick = budget.pick else { return noTaskProposal() }
        if budget.isShort {
            let remaining = TimeBudget.remainingTimeText(minutes: budget.remainingMinutes)
            let needed = TimeBudget.remainingTimeText(minutes: budget.neededMinutes)
            return KairosAgentProposal(
                action: .startFocus,
                title: "要先做“\(pick.task.title)”吗？",
                explanation: "剩下约 \(remaining)，这 \(budget.taskCount) 项大约需要 \(needed)。时间不够一次做完，建议先做最重要的“\(pick.task.title)”。",
                taskID: pick.task.id,
                taskTitle: pick.task.title,
                requiresConfirmation: true
            )
        }
        return KairosAgentProposal(
            action: .startFocus,
            title: "现在先做“\(pick.task.title)”？",
            explanation: "综合截止时间、优先级和所需时长，这是现在最合适的一步。",
            taskID: pick.task.id,
            taskTitle: pick.task.title,
            requiresConfirmation: true
        )
    }

    private static func noTaskProposal() -> KairosAgentProposal {
        KairosAgentProposal(action: .none, title: "目前没有待办任务", explanation: "先添加一个任务，之后我就能帮你推迟、修改时长、完成和重新安排。", requiresConfirmation: false)
    }
}

enum NudgeEngine {
    static let forbiddenPhrases = [
        "到时间了", "必须开始", "该开始了", "该做这项任务了", "立即开始",
        "你已经迟到", "不能再拖", "现在该做", "任务已经到期", "只剩最后"
    ]

    static func localNudge(for task: KairosTask, stage: NudgeStage) -> KairosAgentNudge {
        let trial = trialMinutes(for: task, stage: stage)
        let micro = microStep(for: task, stage: stage)
        let copy = copyDeck(load: task.cognitiveLoad, stage: stage, trial: trial)
        return KairosAgentNudge(
            stage: stage,
            title: copy.title,
            subtitle: copy.subtitle,
            body: copy.body,
            microStep: micro,
            microStepLabel: copy.label,
            primaryActionTitle: copy.primary,
            secondaryActionTitle: copy.secondary,
            trialMinutes: trial,
            source: .local
        )
    }

    static func isJudgmental(_ text: String) -> Bool {
        forbiddenPhrases.contains { text.contains($0) }
    }

    static func merging(model copy: (title: String, subtitle: String, body: String, microStep: String, primary: String, secondary: String), onto fallback: KairosAgentNudge) -> KairosAgentNudge {
        let fields = [copy.title, copy.subtitle, copy.body, copy.microStep, copy.primary, copy.secondary]
        if fields.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJudgmental($0) }) {
            return fallback
        }
        return KairosAgentNudge(
            stage: fallback.stage,
            title: copy.title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: copy.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: copy.body.trimmingCharacters(in: .whitespacesAndNewlines),
            microStep: copy.microStep.trimmingCharacters(in: .whitespacesAndNewlines),
            microStepLabel: fallback.microStepLabel,
            primaryActionTitle: copy.primary.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryActionTitle: copy.secondary.trimmingCharacters(in: .whitespacesAndNewlines),
            trialMinutes: fallback.trialMinutes,
            source: .model
        )
    }

    static func trialMinutes(for task: KairosTask, stage: NudgeStage) -> Int {
        switch stage {
        case .transition: return 0
        case .start: return min(15, max(5, task.estimatedMinutes))
        case .graceRescue: return min(5, max(2, task.estimatedMinutes))
        }
    }

    private static func microStep(for task: KairosTask, stage: NudgeStage) -> String {
        let title = task.title.lowercased()
        let action: String
        if title.contains("leetcode") || title.contains("题") || title.contains("刷") {
            action = "打开题目，只看题面第一句"
        } else if title.contains("读") || title.contains("阅读") || title.contains("read") {
            action = "打开材料，只看第一段"
        } else if title.contains("写") || title.contains("文档") || title.contains("论文") || title.contains("report") || title.contains("essay") {
            action = "打开页面，敲下一行标题即可"
        } else if title.contains("代码") || title.contains("code") || title.contains("开发") || title.contains("编程") || title.contains("debug") {
            action = "打开编辑器，把光标放进去就行"
        } else if title.contains("邮件") || title.contains("email") || title.contains("inbox") {
            action = "打开收件箱，先点开一封"
        } else if title.contains("会议") || title.contains("面试") || title.contains("interview") {
            action = "打开会议页或笔记，写下今天只想确认的一件事"
        } else {
            action = "坐下，把相关页面打开即可"
        }

        switch stage {
        case .transition:
            return "把水杯放到手边，相关窗口先开着。还不用正式开始。"
        case .start:
            return action
        case .graceRescue:
            return "门槛再降一点：\(action)。做完这一下就可以停。"
        }
    }

    private static func copyDeck(load: CognitiveLoad, stage: NudgeStage, trial: Int) -> (title: String, subtitle: String, body: String, label: String, primary: String, secondary: String) {
        switch (stage, load) {
        case (.transition, .high):
            return (
                "先不用开始",
                "给大脑留 10 分钟预热",
                "高认知任务需要一点缓冲。现在只是把环境摆好，不是要求你立刻进入状态。",
                "预热动作",
                "我先把东西摊开",
                "现在还不需要动手"
            )
        case (.transition, .medium):
            return (
                "可以先靠近一点",
                "到点前，先把入口打开",
                "不用进入工作状态。把工具摊开，让下一步变得更容易看见。",
                "预热动作",
                "我先打开入口",
                "现在还不需要动手"
            )
        case (.transition, .low):
            return (
                "轻松热个身就好",
                "这件事很小，先把位置坐好",
                "到点前只需要靠近它。坐下来、打开页面，都算准备完成。",
                "预热动作",
                "我先坐下来",
                "现在还不需要动手"
            )
        case (.start, .high):
            return (
                "这件事看起来大，第一步很小",
                "只需要坐下，把入口打开",
                "高负荷任务容易让人卡住。我们不追求完成，只做一个毫不费力的动作。",
                "破冰第一步",
                "我已经坐好，开始 \(trial) 分钟试水",
                "这次先路过，不算放弃"
            )
        case (.start, .medium):
            return (
                "不用做完，只要开始",
                "打开页面，敲下一行标题即可",
                "启动阻力通常来自把整件事一次想完。先做一个 10 秒内能完成的动作。",
                "破冰第一步",
                "我已经坐好，开始 \(trial) 分钟试水",
                "这次先路过，不算放弃"
            )
        case (.start, .low):
            return (
                "轻轻迈一小步就行",
                "打开软件，坐下来即可",
                "这件事不需要一次做完。先坐下，把入口打开，就算开始了。",
                "破冰第一步",
                "我已经坐好，开始 \(trial) 分钟试水",
                "这次先路过，不算放弃"
            )
        case (.graceRescue, .high):
            return (
                "卡壳不是失败，只是需要更小的入口",
                "接纳现在的状态，做一次 \(trial) 分钟微专注",
                "临近最晚开始也没关系。我们可以把任务降级成一个很小的动作，做完就能停。",
                "降级一步",
                "先试 \(trial) 分钟，随时可以停",
                "先缓一缓，任务还在"
            )
        case (.graceRescue, .medium):
            return (
                "卡住很正常，先做 \(trial) 分钟",
                "无压力降级，不需要追赶",
                "顺延或卡住都不扣分。先用一次很短的微专注，重新碰到这件事。",
                "降级一步",
                "先试 \(trial) 分钟，随时可以停",
                "先缓一缓，任务还在"
            )
        case (.graceRescue, .low):
            return (
                "没关系，我们把步子再缩小",
                "5 分钟微专注就够了",
                "现在开始仍然只需要一个很小的动作。做完可以停，任务会继续等你。",
                "降级一步",
                "先试 \(trial) 分钟，随时可以停",
                "先缓一缓，任务还在"
            )
        }
    }
}
