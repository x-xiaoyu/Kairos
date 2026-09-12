import SwiftUI

struct AskKairosView: View {
    @Environment(\.dismiss) private var dismiss
    let tasks: [KairosTask]
    let onApply: (KairosAgentProposal) -> Void
    @AppStorage("agentServerURL") private var agentServerURL = "http://127.0.0.1:8000"
    @AppStorage("agentMode") private var agentMode = "local"
    @AppStorage("openAIModel") private var openAIModel = "gpt-5-mini"
    @AppStorage("countedTaskCreationStyle") private var countedTaskCreationStyle = "split"
    @State private var input = ""
    @State private var proposal: KairosAgentProposal?
    @State private var isLoading = false
    @State private var responseSource: String?
    @State private var showingPersonalAI = false
    @State private var combineMultipleTasks = false
    @State private var localFlow: GuidedLocalFlow?
    @FocusState private var inputFocused: Bool

    private let examples = ["我今天很累", "推迟 30 分钟", "今晚添加刷两道 LeetCode，40 分钟"]

    var body: some View {
        NavigationStack {
            ZStack {
                KairosTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(.white).frame(width: 48, height: 48).background(KairosTheme.focus, in: Circle())
                            VStack(alignment: .leading, spacing: 3) { Text("告诉 Kairos").font(.title2.bold()); Text("告诉我发生了什么，我来保护你今天剩余的时间。").font(.subheadline).foregroundStyle(.secondary) }
                        }

                        Picker("运行模式", selection: $agentMode) {
                            Text("本地").tag("local")
                            Text("Kairos AI").tag("ai")
                            Text("我的 AI").tag("personal")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: agentMode) { _, mode in
                            proposal = nil; responseSource = nil
                            localFlow = nil
                            if mode == "personal" && KeychainStore.read(account: "openai-api-key") == nil { showingPersonalAI = true }
                        }

                        if let responseSource {
                            Label(sourceLabel(responseSource), systemImage: sourceIcon(responseSource))
                                .font(.caption.bold()).foregroundStyle(responseSource == "bedrock" ? Color.kairosBlue : .secondary)
                        } else {
                            Text(modeDescription)
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        if let proposal {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("KAIROS 建议", systemImage: "wand.and.stars").font(.caption.bold()).foregroundStyle(Color.kairosPurple)
                                Text(proposal.title).font(.title3.bold())
                                Text(proposal.explanation).foregroundStyle(.secondary)
                                if proposal.isMultipleTaskCreation {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(proposal.operations.enumerated()), id: \.offset) { _, operation in
                                            Label(operation.taskTitle ?? "新任务", systemImage: "checklist")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        Picker("创建方式", selection: $combineMultipleTasks) {
                                            Text("拆成 \(proposal.operations.count) 条").tag(false)
                                            Text("合为 1 条").tag(true)
                                        }.pickerStyle(.segmented)
                                    }
                                }
                                if proposal.requiresConfirmation {
                                    HStack { Button("暂时不要") { self.proposal = nil }.buttonStyle(.bordered); Button("确认执行", action: apply).buttonStyle(.borderedProminent) }
                                }
                            }.padding(20).background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 10)).transition(.scale.combined(with: .opacity))
                        } else if agentMode == "local" {
                            if let localFlow {
                                GuidedLocalConversationView(
                                    flow: localFlow,
                                    tasks: activeTasks,
                                    onFlowChange: { self.localFlow = $0 },
                                    onPrepared: { preparedProposal in
                                        proposal = preparedProposal
                                        responseSource = "manual-local"
                                        self.localFlow = nil
                                    },
                                    onCancel: { self.localFlow = nil }
                                )
                                .id(localFlow.id)
                            } else {
                                localActionPrompts
                            }
                        } else {
                            Text("你可以这样说").font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(examples, id: \.self) { example in Button { input = example; submit() } label: { HStack { Text(example); Spacer(); Image(systemName: "arrow.up.right") }.padding(14).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain) }
                        }
                    }.padding(20)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if agentMode != "local" {
                    HStack(spacing: 10) {
                        TextField("告诉 Kairos 发生了什么…", text: $input, axis: .vertical).lineLimit(1...3).focused($inputFocused).submitLabel(.send).onSubmit(submit)
                        Button(action: submit) {
                            if isLoading { ProgressView().frame(width: 34, height: 34) }
                            else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).symbolRenderingMode(.palette).foregroundStyle(.white, Color.kairosIndigo) }
                        }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    }.padding(12).background(.ultraThinMaterial)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showingPersonalAI) { PersonalAIConnectionView() }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: proposal?.id)
        }
    }

    private var activeTasks: [KairosTask] {
        tasks.filter { $0.status != .complete }
    }

    private var localActionPrompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你想让 Kairos 做什么？")
                .font(.headline)
            localPrompt("推迟一个任务", detail: "先选择任务，再设置推迟多久", icon: "clock.arrow.circlepath", color: .kairosCoral) {
                beginTaskAction(.postpone)
            }
            localPrompt("新建一个任务", detail: "填写任务名称、时长和截止时间", icon: "plus.circle.fill", color: .kairosBlue) {
                localFlow = .create
            }
            localPrompt("完成一个任务", detail: "从待办任务中选择一项完成", icon: "checkmark.circle.fill", color: .kairosMint) {
                beginTaskAction(.complete)
            }
            localPrompt("修改任务时长", detail: "选择任务并输入新的预计时间", icon: "timer", color: .kairosPurple) {
                beginTaskAction(.changeDuration)
            }
        }
    }

    private func localPrompt(_ title: String, detail: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func beginTaskAction(_ action: GuidedLocalAction) {
        guard !activeTasks.isEmpty else {
            proposal = KairosAgentProposal(action: .none, title: "目前没有待办任务", explanation: "请先新建任务，再进行这项操作。", requiresConfirmation: false)
            responseSource = "manual-local"
            return
        }
        localFlow = .choose(action)
    }

    private func submit() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        input = ""
        inputFocused = false
        if agentMode == "local" {
            proposal = KairosAdvisor.interpret(message, tasks: tasks, countedTaskStyle: countedTaskCreationStyle)
            combineMultipleTasks = false
            responseSource = "manual-local"
            return
        }
        isLoading = true
        Task {
            do {
                let reply = if agentMode == "personal" {
                    try await PersonalAIService().send(message: message, tasks: tasks, model: openAIModel, countedTaskStyle: countedTaskCreationStyle)
                } else {
                    try await AgentService().send(message: message, tasks: tasks, baseURL: agentServerURL, countedTaskStyle: countedTaskCreationStyle)
                }
                proposal = reply.proposal
                combineMultipleTasks = false
                responseSource = reply.source
            } catch {
                if agentMode == "personal" {
                    proposal = KairosAgentProposal(action: .none, title: "无法使用我的 AI", explanation: error.localizedDescription, requiresConfirmation: false)
                    responseSource = "personal-error"
                    if KeychainStore.read(account: "openai-api-key") == nil { showingPersonalAI = true }
                } else {
                    proposal = KairosAdvisor.interpret(message, tasks: tasks, countedTaskStyle: countedTaskCreationStyle)
                    responseSource = "ai-unavailable"
                }
            }
            isLoading = false
        }
    }

    private func apply() {
        guard let proposal else { return }
        if proposal.isMultipleTaskCreation {
            countedTaskCreationStyle = combineMultipleTasks ? "combined" : "split"
        }
        onApply(combineMultipleTasks ? proposal.combinedTaskCreation() : proposal)
        dismiss()
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "bedrock": "Bedrock AI 在线"
        case "personal-openai": "我的 OpenAI 已连接"
        case "personal-error": "我的 AI 连接失败"
        case "local-fallback": "AI 后端未启用 · 已使用本地规则"
        case "ai-unavailable": "AI 连接失败 · 已使用本地规则"
        default: "本地模式"
        }
    }

    private func sourceIcon(_ source: String) -> String {
        if source == "personal-openai" { return "person.crop.circle.badge.checkmark" }
        if source == "bedrock" { return "cloud.fill" }
        return source.contains("error") || source == "ai-unavailable" ? "exclamationmark.icloud" : "iphone"
    }

    private var modeDescription: String {
        switch agentMode {
        case "ai": "连接 Kairos 的 Bedrock 后端。"
        case "personal": "使用你自己的 OpenAI API 余额。"
        default: "无需网络，使用设备内置规则。"
        }
    }
}

private enum GuidedLocalAction {
    case postpone
    case complete
    case changeDuration
}

private enum GuidedLocalFlow: Identifiable {
    case choose(GuidedLocalAction)
    case create
    case postpone(KairosTask)
    case changeDuration(KairosTask)

    var id: String {
        switch self {
        case .choose(.postpone): "choose-postpone"
        case .choose(.complete): "choose-complete"
        case .choose(.changeDuration): "choose-duration"
        case .create: "create"
        case .postpone(let task): "postpone-\(task.id.uuidString)"
        case .changeDuration(let task): "duration-\(task.id.uuidString)"
        }
    }
}

private struct GuidedLocalConversationView: View {
    let flow: GuidedLocalFlow
    let tasks: [KairosTask]
    let onFlowChange: (GuidedLocalFlow) -> Void
    let onPrepared: (KairosAgentProposal) -> Void
    let onCancel: () -> Void
    @State private var title: String
    @State private var minutes: Int
    @State private var hasDeadline = true
    @State private var deadline: Date

    init(flow: GuidedLocalFlow, tasks: [KairosTask], onFlowChange: @escaping (GuidedLocalFlow) -> Void, onPrepared: @escaping (KairosAgentProposal) -> Void, onCancel: @escaping () -> Void) {
        self.flow = flow
        self.tasks = tasks
        self.onFlowChange = onFlowChange
        self.onPrepared = onPrepared
        self.onCancel = onCancel
        switch flow {
        case .choose, .create:
            _title = State(initialValue: "")
            _minutes = State(initialValue: 30)
        case .postpone(let task):
            _title = State(initialValue: task.title)
            _minutes = State(initialValue: 30)
        case .changeDuration(let task):
            _title = State(initialValue: task.title)
            _minutes = State(initialValue: task.estimatedMinutes)
        }
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now.addingTimeInterval(3_600)
        _deadline = State(initialValue: max(endOfToday, .now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onCancel) {
                Label("返回操作选择", systemImage: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.kairosIndigo)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.kairosPurple, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(promptTitle).font(.headline)
                    Text(promptDetail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))

            switch flow {
            case .choose(let action):
                ForEach(tasks) { task in
                    Button {
                        choose(task, for: action)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.headline)
                                Text("\(task.estimatedMinutes) 分钟\(task.deadline.map { " · \($0.formatted(date: .omitted, time: .shortened)) 截止" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color.kairosIndigo)
                        }
                        .padding(14)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            case .create:
                inputPanel {
                    TextField("任务名称", text: $title)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                    durationEditor(label: "预计时长")
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("截止", selection: $deadline, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                nextButton
            case .postpone(let task):
                selectedTask(task)
                inputPanel { durationEditor(label: "推迟时间") }
                nextButton
            case .changeDuration(let task):
                selectedTask(task)
                inputPanel { durationEditor(label: "新的时长") }
                nextButton
            }
        }
    }

    private var promptTitle: String {
        switch flow {
        case .choose(.postpone): "你想推迟哪项任务？"
        case .choose(.complete): "你完成了哪项任务？"
        case .choose(.changeDuration): "你想修改哪项任务？"
        case .create: "新任务是什么？"
        case .postpone: "你想推迟多久？"
        case .changeDuration: "新的预计时长是多少？"
        }
    }

    private var promptDetail: String {
        switch flow {
        case .choose: "选择一项，Kairos 会继续询问下一步。"
        case .create: "不填写日期时，默认安排在今天并且只执行一次。"
        case .postpone: "选择常用时间，或者直接输入分钟数。"
        case .changeDuration: "修改后会重新计算后续任务的安排。"
        }
    }

    private func inputPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private func selectedTask(_ task: KairosTask) -> some View {
        Label(task.title, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.kairosIndigo)
            .padding(.horizontal, 12)
    }

    private func durationEditor(label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([15, 30, 60], id: \.self) { value in
                    Button("\(value) 分钟") { minutes = value }
                        .buttonStyle(.bordered)
                        .tint(minutes == value ? Color.kairosIndigo : .secondary)
                }
            }
            HStack {
                Text("自定义")
                Spacer()
                HStack(spacing: 5) {
                    TextField("30", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .frame(width: 42)
                    Text("分钟")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.10), in: Capsule())
            }
        }
    }

    private var nextButton: some View {
        Button("确认更改", action: prepare)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!canPrepare)
    }

    private var canPrepare: Bool {
        guard (5...720).contains(minutes) else { return false }
        if case .create = flow {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func prepare() {
        let proposal: KairosAgentProposal
        switch flow {
        case .choose:
            return
        case .create:
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            proposal = KairosAgentProposal(
                action: .createTask,
                title: "新建“\(cleanTitle)”？",
                explanation: hasDeadline ? "预计 \(minutes) 分钟，截止时间为 \(deadline.formatted(date: .abbreviated, time: .shortened))。" : "预计 \(minutes) 分钟，不设置截止时间。",
                taskTitle: cleanTitle,
                value: minutes,
                deadline: hasDeadline ? deadline : nil,
                requiresConfirmation: true
            )
        case .postpone(let task):
            proposal = KairosAgentProposal(
                action: .postpone,
                title: "将“\(task.title)”推迟 \(minutes) 分钟？",
                explanation: "确认后会重新计算今天剩余任务的开始时间。",
                taskID: task.id,
                taskTitle: task.title,
                value: minutes,
                requiresConfirmation: true
            )
        case .changeDuration(let task):
            proposal = KairosAgentProposal(
                action: .changeDuration,
                title: "把“\(task.title)”改为 \(minutes) 分钟？",
                explanation: "确认后会重新计算任务安排。",
                taskID: task.id,
                taskTitle: task.title,
                value: minutes,
                requiresConfirmation: true
            )
        }
        onPrepared(proposal)
    }

    private func choose(_ task: KairosTask, for action: GuidedLocalAction) {
        switch action {
        case .postpone:
            onFlowChange(.postpone(task))
        case .changeDuration:
            onFlowChange(.changeDuration(task))
        case .complete:
            onPrepared(KairosAgentProposal(
                action: .complete,
                title: "完成“\(task.title)”？",
                explanation: "确认后，这项任务会进入完成历史。",
                taskID: task.id,
                taskTitle: task.title,
                requiresConfirmation: true
            ))
        }
    }
}
