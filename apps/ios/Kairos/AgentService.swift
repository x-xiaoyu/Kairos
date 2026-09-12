import Foundation

struct AgentReply {
    let proposal: KairosAgentProposal
    let source: String
}

enum AgentServiceError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Agent 服务地址无效。"
        case .invalidResponse: "Agent 服务返回了无法识别的内容。"
        }
    }
}

struct AgentService {
    func send(message: String, tasks: [KairosTask], baseURL: String, countedTaskStyle: String = "split") async throws -> AgentReply {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw AgentServiceError.invalidURL }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "agent", "chat"].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else { throw AgentServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(AgentChatRequestDTO(
            message: message,
            locale: "zh-CN",
            now: .now,
            countedTaskStyle: countedTaskStyle,
            tasks: tasks.map(AgentTaskDTO.init)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw AgentServiceError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(AgentChatResponseDTO.self, from: data)
        return AgentReply(proposal: result.makeProposal(), source: result.source)
    }
}

private struct AgentChatRequestDTO: Encodable {
    let message: String
    let locale: String
    let now: Date
    let countedTaskStyle: String
    let tasks: [AgentTaskDTO]

    enum CodingKeys: String, CodingKey {
        case message, locale, now, tasks
        case countedTaskStyle = "counted_task_style"
    }
}

private struct AgentTaskDTO: Encodable {
    let id: String
    let title: String
    let goal: String?
    let deadline: Date?
    let estimatedMinutes: Int
    let priority: Int
    let status: String
    let cognitiveLoad: String
    let interruptible: Bool
    let deadlineType: String

    enum CodingKeys: String, CodingKey {
        case id, title, goal, deadline, priority, status, interruptible
        case estimatedMinutes = "estimated_minutes"
        case cognitiveLoad = "cognitive_load"
        case deadlineType = "deadline_type"
    }

    init(_ task: KairosTask) {
        id = task.id.uuidString
        title = task.title
        goal = task.goal.isEmpty ? nil : task.goal
        deadline = task.deadline
        estimatedMinutes = task.estimatedMinutes
        priority = task.priority
        status = task.status == .inProgress ? "in_progress" : task.status.rawValue
        cognitiveLoad = task.cognitiveLoad.rawValue
        interruptible = task.isInterruptible
        deadlineType = task.deadlineType.rawValue
    }
}

struct AgentChatResponseDTO: Decodable {
    let assistantMessage: String
    let proposedActions: [AgentActionDTO]
    let planSummary: String
    let consequences: [String]
    let requiresConfirmation: Bool
    let source: String

    enum CodingKeys: String, CodingKey {
        case assistantMessage = "assistant_message"
        case proposedActions = "proposed_actions"
        case planSummary = "plan_summary"
        case consequences, source
        case requiresConfirmation = "requires_confirmation"
    }

    func makeProposal() -> KairosAgentProposal {
        guard let action = proposedActions.first else {
            return KairosAgentProposal(action: .none, title: assistantMessage, explanation: planSummary, requiresConfirmation: false)
        }
        let details = ([planSummary] + consequences).filter { !$0.isEmpty }.joined(separator: "\n")
        return KairosAgentProposal(
            action: action.localAction,
            title: assistantMessage,
            explanation: details,
            taskID: action.taskID.flatMap(UUID.init(uuidString:)),
            taskTitle: action.taskTitle,
            value: action.value,
            deadline: action.deadline,
            requiresConfirmation: action.requiresConfirmation && requiresConfirmation,
            additionalOperations: proposedActions.dropFirst().map(\.operation)
        )
    }
}

struct AgentActionDTO: Decodable {
    let action: String
    let taskID: String?
    let taskTitle: String?
    let value: Int?
    let deadline: Date?
    let requiresConfirmation: Bool

    enum CodingKeys: String, CodingKey {
        case action, value, deadline
        case taskID = "task_id"
        case taskTitle = "task_title"
        case requiresConfirmation = "requires_confirmation"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
        taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle)
        value = try container.decodeIfPresent(Int.self, forKey: .value)
        requiresConfirmation = try container.decode(Bool.self, forKey: .requiresConfirmation)

        // AI providers may emit valid ISO-8601 dates with fractional seconds or a
        // date-only value. A single unfamiliar date should not discard the entire
        // recommendation, so parse the common forms and otherwise leave it unset.
        if let rawDeadline = try container.decodeIfPresent(String.self, forKey: .deadline) {
            deadline = Self.parseDeadline(rawDeadline)
        } else {
            deadline = nil
        }
    }

    private static func parseDeadline(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: value) { return date }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.calendar = Calendar(identifier: .gregorian)
        dateOnly.timeZone = .current
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }

    var operation: KairosAgentOperation {
        KairosAgentOperation(
            action: localAction,
            taskID: taskID.flatMap(UUID.init(uuidString:)),
            taskTitle: taskTitle,
            value: value,
            deadline: deadline
        )
    }

    var localAction: KairosAgentAction {
        switch action {
        case "create_task": .createTask
        case "postpone_task": .postpone
        case "change_duration": .changeDuration
        case "change_priority": .changePriority
        case "complete_task": .complete
        case "replan": .replan
        default: .none
        }
    }
}
