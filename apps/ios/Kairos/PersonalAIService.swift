import Foundation

enum PersonalAIError: LocalizedError {
    case notConnected
    case invalidResponse
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "请先连接你的 OpenAI API 账户。"
        case .invalidResponse: "OpenAI 返回了无法识别的内容。"
        case .provider(let message): message
        }
    }
}

struct PersonalAIService {
    func send(message: String, tasks: [KairosTask], model: String, countedTaskStyle: String = "split") async throws -> AgentReply {
        guard let apiKey = KeychainStore.read(account: "openai-api-key"), !apiKey.isEmpty else { throw PersonalAIError.notConnected }
        let taskContext = tasks.filter { $0.status != .complete }.map {
            ["id": $0.id.uuidString, "title": $0.title, "minutes": $0.estimatedMinutes, "priority": $0.priority] as [String: Any]
        }
        let contextData = try JSONSerialization.data(withJSONObject: taskContext)
        let context = String(data: contextData, encoding: .utf8) ?? "[]"
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "assistant_message": ["type": "string"],
                "proposed_actions": [
                    "type": "array",
                    "items": [
                        "type": "object", "additionalProperties": false,
                        "properties": [
                            "action": ["type": "string", "enum": ["create_task", "postpone_task", "change_duration", "change_priority", "complete_task", "replan", "start_focus", "no_action"]],
                            "task_id": ["type": ["string", "null"]],
                            "task_title": ["type": ["string", "null"]],
                            "value": ["type": ["integer", "null"]],
                            "deadline": ["type": ["string", "null"]],
                            "requires_confirmation": ["type": "boolean"],
                        ],
                        "required": ["action", "task_id", "task_title", "value", "deadline", "requires_confirmation"],
                    ],
                ],
                "plan_summary": ["type": "string"],
                "consequences": ["type": "array", "items": ["type": "string"]],
                "requires_confirmation": ["type": "boolean"],
                "source": ["type": "string", "enum": ["personal-openai"]],
            ],
            "required": ["assistant_message", "proposed_actions", "plan_summary", "consequences", "requires_confirmation", "source"],
        ]
        let localFormatter = ISO8601DateFormatter()
        localFormatter.formatOptions = [.withInternetDateTime]
        localFormatter.timeZone = .current
        let localNow = localFormatter.string(from: .now)
        let today = Date.now.formatted(.iso8601.year().month().day())
        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-5-mini" : model,
            "instructions": """
            你是 Kairos，一个冷静、不评判的个人执行 Agent。理解自然中文，根据用户输入和任务上下文提出操作，但绝不直接执行。涉及数据变化必须 requires_confirmation=true。
            使用这些确定默认值，不要为它们追问：未说日期=设备时区中的今天；未说频率=仅一次；未说时长=每条30分钟；未说具体时间=今天23:59。所有 deadline 必须带设备时区偏移的 ISO 8601。
            用户说刷/做 N 个或 N 道题时，默认创建 N 个 create_task action，并用“（1/N）”编号。只有明确说合并，或用户学习偏好是 combined，才创建一条。若只给一个总时长，平均分给 N 条；若说每题/每个，则每条使用该时长。
            不要询问时区、日期、频率、拆分方式、时长或优先级；采用默认值并在 assistant_message 简短说明。相同截止时间的 action 保持用户说出的顺序。
            若用户问今天来不来得及、该先做什么、时间不够、或哪个最重要：先估算所需总时长与剩余时间。不够一次做完时，只提出 start_focus 一项最重要的任务，明确说明时间不够，并 requires_confirmation=true 问用户是否先做它。不要同时催多项。
            当前用户的计数任务偏好：\(countedTaskStyle)。
            """,
            "input": "设备时区：\(TimeZone.current.identifier)（GMT\(TimeZone.current.secondsFromGMT() / 3600)）\n本地当前时间：\(localNow)\n本地今天：\(today)\n当前任务：\(context)\n用户：\(message)",
            "text": ["format": ["type": "json_schema", "name": "kairos_agent_response", "strict": true, "schema": schema]],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PersonalAIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw PersonalAIError.provider(error?["message"] as? String ?? "OpenAI 请求失败（\(http.statusCode)）。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersonalAIError.invalidResponse
        }
        let nestedText = (object["output"] as? [[String: Any]])?
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .first { $0["type"] as? String == "output_text" }?["text"] as? String
        guard let rawText = (object["output_text"] as? String) ?? nestedText else {
            let refusal = (object["output"] as? [[String: Any]])?
                .compactMap { $0["content"] as? [[String: Any]] }
                .flatMap { $0 }
                .first { $0["type"] as? String == "refusal" }?["refusal"] as? String
            throw PersonalAIError.provider(refusal ?? "OpenAI 没有返回可读取的文字内容，请重试。")
        }

        let text = Self.removingMarkdownFence(from: rawText)
        guard let replyData = text.data(using: .utf8) else { throw PersonalAIError.invalidResponse }
        do {
            let result = try JSONDecoder().decode(AgentChatResponseDTO.self, from: replyData)
            return AgentReply(proposal: result.makeProposal(), source: "personal-openai")
        } catch {
            throw PersonalAIError.provider("OpenAI 已连接，但回复格式暂时无法解析。请再试一次。")
        }
    }

    func generateNudge(task: KairosTask, stage: NudgeStage, fallback: KairosAgentNudge) async throws -> KairosAgentNudge {
        guard let apiKey = KeychainStore.read(account: "openai-api-key"), !apiKey.isEmpty else { throw PersonalAIError.notConnected }
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": ["type": "string"],
                "subtitle": ["type": "string"],
                "body": ["type": "string"],
                "micro_step": ["type": "string"],
                "primary_action": ["type": "string"],
                "secondary_action": ["type": "string"],
            ],
            "required": ["title", "subtitle", "body", "micro_step", "primary_action", "secondary_action"],
        ]
        let stageHint: String
        switch stage {
        case .transition: stageHint = "transition：计划开始前的心理预热。还不用正式开始，只帮助把环境摆好。"
        case .start: stageHint = "start：到点启动。只给一个 10 秒内能完成的最小物理动作。"
        case .graceRescue: stageHint = "graceRescue：用户卡住、顺延，或接近最晚安全开始时间。先接纳，再给无压力的 5 分钟微专注降级。"
        }
        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "openAIModel").flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-5-mini",
            "instructions": """
            你是 Kairos，一位冷静、不评判的 ADHD 执行功能辅助 Agent。目标是降低启动阻力（Activation Friction）：认知降噪、微动作破冰、防内疚。
            禁止使用评判或闹钟式措辞，包括：到时间了、必须开始、该开始了、该做这项任务了、立即开始、你已经迟到、不能再拖、现在该做、任务已经到期、只剩最后。
            文案要短、具体、可执行。micro_step 必须是一个身体或界面上的最小动作，而不是“开始认真做”。
            主按钮给宽慰感，关闭/顺延按钮必须无负罪感。
            """,
            "input": """
            阶段：\(stage.rawValue)（\(stageHint)）
            任务：\(task.title)
            目标：\(task.goal.isEmpty ? "未填写" : task.goal)
            认知负荷：\(task.cognitiveLoad.rawValue)
            预计时长：\(task.estimatedMinutes) 分钟
            试水时长：\(fallback.trialMinutes) 分钟
            本地兜底文案：title=\(fallback.title)；micro_step=\(fallback.microStep)
            """,
            "text": ["format": ["type": "json_schema", "name": "kairos_nudge", "strict": true, "schema": schema]],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PersonalAIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw PersonalAIError.provider(error?["message"] as? String ?? "OpenAI 请求失败（\(http.statusCode)）。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersonalAIError.invalidResponse
        }
        let nestedText = (object["output"] as? [[String: Any]])?
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .first { $0["type"] as? String == "output_text" }?["text"] as? String
        guard let rawText = (object["output_text"] as? String) ?? nestedText else {
            throw PersonalAIError.invalidResponse
        }
        let text = Self.removingMarkdownFence(from: rawText)
        guard let replyData = text.data(using: .utf8) else { throw PersonalAIError.invalidResponse }
        let dto = try JSONDecoder().decode(AgentNudgeDTO.self, from: replyData)
        return NudgeEngine.merging(
            model: (dto.title, dto.subtitle, dto.body, dto.microStep, dto.primaryAction, dto.secondaryAction),
            onto: fallback
        )
    }

    func refineTimeShortRecommendation(
        _ fallback: KairosRecommendation,
        pick: PlannedTask,
        budget: TimeBudgetSnapshot
    ) async throws -> KairosRecommendation {
        guard let apiKey = KeychainStore.read(account: "openai-api-key"), !apiKey.isEmpty else {
            throw PersonalAIError.notConnected
        }
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "headline": ["type": "string"],
                "reason": ["type": "string"],
                "consequence": ["type": "string"],
                "confirm_prompt": ["type": "string"],
                "primary_action": ["type": "string"],
                "secondary_action": ["type": "string"],
            ],
            "required": ["headline", "reason", "consequence", "confirm_prompt", "primary_action", "secondary_action"],
        ]
        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "openAIModel").flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-5-mini",
            "instructions": """
            你是 Kairos，一位冷静、不评判的 ADHD 执行功能辅助 Agent。
            确定性排程器已经选定唯一优先任务；你只能精炼中文表达，不能换任务、修改时间数学或暗示同时开始其他任务。
            清楚说明今天时间不足，只提出一个选择，并以问题向用户确认是否先做选定任务。
            避免责备、恐吓和“必须、不能再拖、立即开始”等措辞。所有字段保持简短。
            """,
            "input": """
            唯一选定任务：\(pick.task.title)
            剩余时间：\(TimeBudget.remainingTimeText(minutes: budget.remainingMinutes))
            \(budget.taskCount) 项预计总耗时：\(TimeBudget.remainingTimeText(minutes: budget.neededMinutes))
            本地兜底：
            headline=\(fallback.headline)
            reason=\(fallback.reason)
            consequence=\(fallback.consequence)
            confirm_prompt=\(fallback.confirmPrompt)
            """,
            "text": ["format": ["type": "json_schema", "name": "kairos_time_short_recommendation", "strict": true, "schema": schema]],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PersonalAIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw PersonalAIError.provider(error?["message"] as? String ?? "OpenAI 请求失败（\(http.statusCode)）。")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersonalAIError.invalidResponse
        }
        let nestedText = (object["output"] as? [[String: Any]])?
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .first { $0["type"] as? String == "output_text" }?["text"] as? String
        guard let rawText = (object["output_text"] as? String) ?? nestedText else {
            throw PersonalAIError.invalidResponse
        }
        let text = Self.removingMarkdownFence(from: rawText)
        guard let replyData = text.data(using: .utf8) else { throw PersonalAIError.invalidResponse }
        let dto = try JSONDecoder().decode(TimeShortRecommendationDTO.self, from: replyData)
        let fields = [dto.headline, dto.reason, dto.consequence, dto.confirmPrompt, dto.primaryAction, dto.secondaryAction]
        guard fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !NudgeEngine.isJudgmental(fields.joined(separator: " ")),
              dto.headline.contains(pick.task.title),
              dto.confirmPrompt.contains(pick.task.title),
              dto.primaryAction.contains(pick.task.title) else {
            return fallback
        }
        return KairosRecommendation(
            eyebrow: fallback.eyebrow,
            headline: dto.headline,
            reason: dto.reason,
            consequence: dto.consequence,
            confirmPrompt: dto.confirmPrompt,
            primaryActionTitle: dto.primaryAction,
            secondaryActionTitle: dto.secondaryAction,
            urgency: fallback.urgency,
            pickID: fallback.pickID,
            isTimeShort: fallback.isTimeShort,
            confirmToken: fallback.confirmToken
        )
    }

    private static func removingMarkdownFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TimeShortRecommendationDTO: Decodable {
    let headline: String
    let reason: String
    let consequence: String
    let confirmPrompt: String
    let primaryAction: String
    let secondaryAction: String

    enum CodingKeys: String, CodingKey {
        case headline, reason, consequence
        case confirmPrompt = "confirm_prompt"
        case primaryAction = "primary_action"
        case secondaryAction = "secondary_action"
    }
}

private struct AgentNudgeDTO: Decodable {
    let title: String
    let subtitle: String
    let body: String
    let microStep: String
    let primaryAction: String
    let secondaryAction: String

    enum CodingKeys: String, CodingKey {
        case title, subtitle, body
        case microStep = "micro_step"
        case primaryAction = "primary_action"
        case secondaryAction = "secondary_action"
    }
}
