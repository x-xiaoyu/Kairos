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
                            "action": ["type": "string", "enum": ["create_task", "postpone_task", "change_duration", "change_priority", "complete_task", "replan", "no_action"]],
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

    private static func removingMarkdownFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
