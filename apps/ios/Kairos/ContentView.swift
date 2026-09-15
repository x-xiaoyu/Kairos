import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \KairosTask.createdAt) private var tasks: [KairosTask]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var events: [ActivityEvent]
    @StateObject private var notifications = NotificationManager()
    @StateObject private var calendar = CalendarManager()
    @StateObject private var weather = WeatherManager()
    @AppStorage("saveFocusToCalendar") private var saveFocusToCalendar = true
    @AppStorage("weatherUnit") private var weatherUnit = "automatic"
    @AppStorage("personalMotto") private var personalMotto = "此刻最重要的事"
    @AppStorage("personalSubgoal") private var personalSubgoal = "最稳妥的下一步已经排在最上面。"
    @State private var showingNewTask = false
    @State private var showingReview = false
    @State private var showingRoutines = false
    @State private var showingSettings = false
    @State private var showingAgent = false
    @State private var showingHeaderEditor = false
    @State private var calendarSaveMessage: String?
    @State private var urgentTask: KairosTask?
    @State private var startReminderTask: KairosTask?
    @State private var lastUrgencyPromptAt = Date.distantPast
    @State private var focusTask: KairosTask?
    @State private var restoredFocus: PersistedFocusState?
    @State private var graceOffer: GraceMessageOffer?
    @State private var now = Date.now

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var timeBias: TimeBiasProfile { TimeBiasReflector.profile(tasks: tasks, events: events) }
    private var plan: [PlannedTask] { Planner.makePlan(tasks: tasks, now: now, bias: timeBias) }
    private var notificationFingerprint: [String] {
        plan.map { item in
            "\(item.task.id)-\(item.task.title)-\(item.task.deadline?.timeIntervalSince1970 ?? 0)-\(item.task.scheduledStart?.timeIntervalSince1970 ?? 0)-\(item.latestSafeStart?.timeIntervalSince1970 ?? 0)-\(item.task.isPrimaryCountdown)-\(item.task.dayOrder)-\(item.task.cognitiveLoad.rawValue)-\(item.task.estimatedMinutes)-\(item.task.timeBiasCalibrationRaw)-\(timeBias.overallRatio)"
        }
    }
    private var countdownTask: KairosTask? {
        tasks.first(where: { $0.status != .complete && $0.isPrimaryCountdown && $0.deadline != nil })
            ?? plan.first(where: { $0.task.deadline != nil })?.task
    }
    private var nextTaskBiasInsight: TimeBiasInsight? {
        guard let task = plan.first?.task, timeBias.shouldCalibrate(task.cognitiveLoad) else { return nil }
        return TimeBiasReflector.insight(for: task.cognitiveLoad, tasks: tasks, events: events)
            ?? timeBias.insights.first { $0.isCalibration }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KairosTheme.background.ignoresSafeArea()
                Circle().fill(Color.kairosSun.opacity(0.18)).frame(width: 240).blur(radius: 8).offset(x: 160, y: -310)
                Circle().fill(Color.kairosPurple.opacity(0.12)).frame(width: 280).blur(radius: 16).offset(x: -170, y: 300)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        topHeader
                        greeting
                        if let insight = nextTaskBiasInsight, let current = plan.first {
                            TimeBiasInsightBubble(
                                text: insight.message(forEstimatedMinutes: current.task.estimatedMinutes),
                                choice: current.task.timeBiasCalibration,
                                onReserve: { acceptTimeBias(for: current.task, insight: insight) },
                                onKeepEstimate: { declineTimeBias(for: current.task) }
                            )
                        }
                        if let recommendation = KairosAdvisor.recommendation(for: plan) { agentCard(recommendation) }
                        if plan.isEmpty { emptyState } else { planList }
                    }.padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
            .sheet(isPresented: $showingNewTask) { NavigationStack { TaskEditor() } }
            .navigationDestination(isPresented: $showingReview) { DayReviewView(events: events, completed: tasks.filter { $0.status == .complete }, tasks: tasks) }
            .navigationDestination(isPresented: $showingRoutines) { HabitsView() }
            .navigationDestination(isPresented: $showingSettings) { KairosSettingsView() }
            .navigationDestination(isPresented: $showingAgent) { AskKairosView(tasks: tasks, onApply: applyAgentProposal) }
            .sheet(isPresented: $showingHeaderEditor) {
                PersonalHeaderEditor(motto: $personalMotto, subgoal: $personalSubgoal)
            }
            .sheet(item: $graceOffer) { offer in
                GraceMessageSheet(task: offer.task, trigger: offer.trigger, revisedStart: offer.revisedStart)
            }
            .fullScreenCover(item: $startReminderTask) { task in
                StartTaskReminderView(
                    task: task,
                    kind: .scheduledStart,
                    latestSafeStart: plan.first(where: { $0.task.id == task.id })?.latestSafeStart,
                    onStart: { beginFromStartReminder(task) },
                    onDismiss: { dismissStartReminder(task) },
                    onComposeGrace: { offerGrace(fromReminder: task, kind: .scheduledStart) }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $urgentTask) { task in
                StartTaskReminderView(
                    task: task,
                    kind: .deadline,
                    latestSafeStart: plan.first(where: { $0.task.id == task.id })?.latestSafeStart,
                    onStart: { beginFromUrgentReminder(task) },
                    onDismiss: { urgentTask = nil },
                    onComposeGrace: { offerGrace(fromReminder: task, kind: .deadline) }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $focusTask) { task in FocusView(task: task, availableTasks: tasks, restored: restoredFocus, log: { action, focusedTask, detail in
                log(action, focusedTask.title, detail)
            }, onComplete: { completedTask, startedAt, endedAt, focusedSeconds in
                guard saveFocusToCalendar else { return }
                Task {
                    let saved = await calendar.saveFocusSession(task: completedTask, startedAt: startedAt, endedAt: endedAt, focusedSeconds: focusedSeconds)
                    log(saved ? "Added to Calendar" : "Calendar save failed", completedTask.title, saved ? "已把这段真实专注写入日历。" : (calendar.lastError ?? "日历不可用。"))
                    calendarSaveMessage = saved ? "已将“\(completedTask.title)”的专注时段存入 Apple 日历。" : (calendar.lastError ?? "无法写入 Apple 日历。")
                }
            }) }
            .alert("Apple 日历", isPresented: Binding(get: { calendarSaveMessage != nil }, set: { if !$0 { calendarSaveMessage = nil } })) {
                Button("好") { calendarSaveMessage = nil }
            } message: {
                Text(calendarSaveMessage ?? "")
            }
            .task {
                weather.refresh()
                await notifications.requestPermission()
                await notifications.reschedule(plan: plan)
                WidgetSnapshotStore.update(plan: plan, primaryCountdown: countdownTask)
                try? await Task.sleep(for: .milliseconds(500))
                restorePersistedFocus()
                if focusTask == nil { checkForStartReminder() }
                if startReminderTask == nil { checkForUrgentTask() }
            }
            .onChange(of: notificationFingerprint) { _, _ in
                WidgetSnapshotStore.update(plan: plan, primaryCountdown: countdownTask)
                Task { await notifications.reschedule(plan: plan) }
                checkForStartReminder()
            }
            .onChange(of: focusTask) { _, task in
                if task == nil { restoredFocus = nil }
            }
            .onReceive(clock) {
                now = $0
                checkForStartReminder()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    now = .now
                    checkForStartReminder()
                    if startReminderTask == nil { checkForUrgentTask() }
                }
            }
        }
        .tint(Color.kairosIndigo)
    }

    private var bottomDock: some View {
        HStack {
            dockButton("回顾", icon: "clock.arrow.circlepath") { showingReview = true }
            dockButton("习惯", icon: "checkmark.circle.fill") { showingRoutines = true }
            dockButton("Kairos", icon: "message.fill") { showingAgent = true }
            dockButton("设置", icon: "gearshape.fill") { showingSettings = true }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func dockButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 18, weight: .semibold)); Text(title).font(.caption2.weight(.semibold)) }
                .frame(maxWidth: .infinity)
        }.buttonStyle(.plain).foregroundStyle(Color.kairosIndigo).accessibilityLabel(title)
    }

    private func agentCard(_ recommendation: KairosRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(recommendation.headline).font(.title2.bold())
            Label(recommendation.consequence, systemImage: "arrow.triangle.branch").font(.subheadline.weight(.medium)).foregroundStyle(Color.kairosCoral)
            if let current = plan.first {
                HStack(spacing: 8) {
                    Button("开始当前任务") { startFocus(current.task, detail: "Kairos recommended starting now.") }
                        .buttonStyle(.borderedProminent)
                    if let next = plan.dropFirst().first,
                       Planner.isScheduledOnSameDay(current.task, next.task, now: now) {
                        Button("顺延当前任务") { postponeCurrent(current.task, next: next.task) }
                            .buttonStyle(.bordered)
                    }
                    Button("结束任务") { complete(current.task) }
                        .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
                .controlSize(.small)
                if current.risk == .high || current.risk == .critical {
                    Button("需要对外说明？一键起草") {
                        presentGrace(for: current.task, trigger: graceTrigger(for: current))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [.white.opacity(0.92), Color.kairosPurple.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.kairosPurple.opacity(0.22)))
        .shadow(color: Color.kairosPurple.opacity(0.12), radius: 18, y: 8)
    }

    private var topHeader: some View {
        HStack(alignment: .top) {
            Button { weather.refresh() } label: {
                HStack(spacing: 9) {
                    Image(systemName: weather.symbol)
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                    VStack(alignment: .leading, spacing: 2) {
                        if let temperature = weather.temperature {
                            Text(temperature)
                                .font(.title3.bold())
                                .foregroundStyle(Color.kairosInk)
                        }
                        Text(weather.locationName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.kairosInk.opacity(0.62))
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(weather.condition)，地点：\(weather.locationName)\(weather.temperature.map { "，气温 \($0)" } ?? "")。点按刷新天气。")

            Spacer()
            if let countdownTask {
                DeadlineDayCountdown(task: countdownTask, now: now)
            }
        }
    }

    private var greeting: some View {
        Button { showingHeaderEditor = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                }
                Text(personalMotto)
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .multilineTextAlignment(.leading)
                Text(personalSubgoal)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑个人标语与子目标")
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "message.fill").font(.system(size: 34)).foregroundStyle(Color.kairosIndigo)
            Text("今天还没有任务").font(.title2.bold())
            Text("先写下一件要做的事、截止时间和预计时长。Kairos 会告诉你最晚该什么时候开始。").multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button { showingAgent = true } label: { Label("告诉 Kairos", systemImage: "message.fill") }.buttonStyle(.borderedProminent)
                Button("手动添加任务") { showingNewTask = true }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity).padding(32).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
    }

    private var planList: some View {
        VStack(spacing: 14) {
            ForEach(Array(plan.enumerated()), id: \.element.id) { index, item in
                TaskCard(item: item, isNext: index == 0, accent: KairosTheme.accents[index % KairosTheme.accents.count], onFocus: { log("Focus started", item.task.title, "\(item.task.estimatedMinutes) minute countdown started."); focusTask = item.task }, onComplete: {
                    item.task.status = .complete; log("Completed", item.task.title, "Task marked complete.")
                }, onPostpone: {
                    Planner.postponeWithinDay(item.task, among: tasks, minutes: 30, now: now)
                    log("Postponed", item.task.title, "Moved later among tasks scheduled for the same day.")
                    presentGrace(for: item.task, trigger: .postponed, revisedStart: revisedStart(for: item.task))
                }, onGrace: (item.risk == .high || item.risk == .critical) ? { presentGrace(for: item.task, trigger: graceTrigger(for: item)) } : nil, onDelete: {
                    log("Deleted", item.task.title, "Task deleted after confirmation.")
                    context.delete(item.task)
                })
            }
        }
    }

    private func log(_ action: String, _ task: String, _ detail: String) { context.insert(ActivityEvent(action: action, taskTitle: task, detail: detail)) }

    private func startFocus(_ task: KairosTask, detail: String) {
        restoredFocus = nil
        log("Focus started", task.title, detail)
        focusTask = task
    }

    private func restorePersistedFocus() {
        guard focusTask == nil, startReminderTask == nil, urgentTask == nil, let raw = FocusSessionStore.load() else { return }
        let reconciled = FocusSessionStore.reconcile(state: raw, now: .now)
        let surviving = reconciled.sessions.compactMap { record -> PersistedFocusSession? in
            tasks.contains { $0.id == record.taskId && $0.status != .complete } ? record : nil
        }
        guard let firstID = surviving.first?.taskId, let first = tasks.first(where: { $0.id == firstID }) else {
            FocusSessionStore.clear()
            return
        }
        var next = reconciled
        next.sessions = surviving
        restoredFocus = next
        FocusSessionStore.save(next)
        log("Focus restored", first.title, "Recovered \(surviving.count) in-progress session(s) after Kairos relaunched.")
        focusTask = first
    }

    private func acceptTimeBias(for task: KairosTask, insight: TimeBiasInsight) {
        let reserved = TimeBiasReflector.reservedMinutes(estimated: task.estimatedMinutes, biasRatio: insight.biasRatio)
        task.estimatedMinutes = reserved
        task.timeBiasCalibration = .accepted
        log("Time bias accepted", task.title, "Reserved \(reserved) minutes after \(insight.sampleCount) focus records.")
        now = .now
    }

    private func declineTimeBias(for task: KairosTask) {
        task.timeBiasCalibration = .declined
        log("Time bias declined", task.title, "Kept the written estimate; risk warnings are more sensitive.")
        now = .now
    }

    private func checkForUrgentTask() {
        guard focusTask == nil, startReminderTask == nil, urgentTask == nil, Date.now.timeIntervalSince(lastUrgencyPromptAt) >= 300 else { return }
        let candidate = tasks
            .filter { task in
                guard task.status != .complete, let deadline = task.deadline else { return false }
                return deadline.timeIntervalSinceNow <= 30 * 60
            }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            .first
        guard let candidate else { return }
        now = .now
        lastUrgencyPromptAt = .now
        urgentTask = candidate
    }

    private func checkForStartReminder() {
        guard scenePhase == .active, focusTask == nil, startReminderTask == nil else { return }
        let current = Date.now
        let candidate = tasks
            .filter { task in
                guard task.status != .complete, let start = task.scheduledStart else { return false }
                guard start <= current, current.timeIntervalSince(start) <= 24 * 60 * 60 else { return false }
                return !UserDefaults.standard.bool(forKey: startReminderDismissalKey(for: task))
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }
            .first
        startReminderTask = candidate
    }

    private func startReminderDismissalKey(for task: KairosTask) -> String {
        "dismissed-start-reminder-\(task.id)-\(Int(task.scheduledStart?.timeIntervalSince1970 ?? 0))"
    }

    private func dismissStartReminder(_ task: KairosTask) {
        UserDefaults.standard.set(true, forKey: startReminderDismissalKey(for: task))
        notifications.clearStartReminder(for: task.id)
        startReminderTask = nil
    }

    private func beginFromStartReminder(_ task: KairosTask) {
        UserDefaults.standard.set(true, forKey: startReminderDismissalKey(for: task))
        notifications.clearStartReminder(for: task.id)
        startReminderTask = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            startFocus(task, detail: "Started from the scheduled start reminder.")
        }
    }

    private func beginFromUrgentReminder(_ task: KairosTask) {
        urgentTask = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            startFocus(task, detail: "Started from an urgent deadline reminder.")
        }
    }

    private func postponeCurrent(_ current: KairosTask, next: KairosTask) {
        Planner.postponeWithinDay(current, among: tasks, minutes: 30, now: now)
        log("Postponed", current.title, "Moved later in today's queue; \(next.title) is now next.")
        presentGrace(for: current, trigger: .postponed, revisedStart: revisedStart(for: current))
    }

    private func presentGrace(for task: KairosTask, trigger: GraceMessageTrigger, revisedStart: Date? = nil) {
        graceOffer = GraceMessageOffer(task: task, trigger: trigger, revisedStart: revisedStart)
    }

    private func revisedStart(for task: KairosTask) -> Date? {
        Planner.makePlan(tasks: tasks, now: now, bias: timeBias).first(where: { $0.task.id == task.id })?.start
    }

    private func graceTrigger(for item: PlannedTask) -> GraceMessageTrigger {
        if let deadline = item.task.deadline, deadline <= now { return .overdue }
        if let start = item.task.scheduledStart, start <= now { return .missedStart }
        return .highRisk
    }

    private func offerGrace(fromReminder task: KairosTask, kind: TaskReminderKind) {
        let trigger: GraceMessageTrigger
        if kind == .deadline {
            trigger = (task.deadline.map { $0 <= .now } ?? false) ? .overdue : .highRisk
        } else {
            trigger = .missedStart
        }
        if kind == .scheduledStart {
            dismissStartReminder(task)
        } else {
            urgentTask = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            presentGrace(for: task, trigger: trigger)
        }
    }

    private func complete(_ task: KairosTask) {
        task.status = .complete
        log("Completed", task.title, "Task ended from the Kairos recommendation.")
    }

    private func applyAgentProposal(_ proposal: KairosAgentProposal) {
        for operation in proposal.operations {
            applyAgentOperation(operation, explanation: proposal.explanation)
        }
    }

    private func applyAgentOperation(_ operation: KairosAgentOperation, explanation: String) {
        switch operation.action {
        case .createTask:
            let title = operation.taskTitle ?? "新任务"
            if operation.isPrimaryCountdown {
                for existing in tasks { existing.isPrimaryCountdown = false }
            }
            let task = KairosTask(title: title, deadline: operation.deadline, estimatedMinutes: operation.value ?? 30, priority: 3, cognitiveLoad: .medium, deadlineType: operation.deadline == nil ? .none : .soft, isPrimaryCountdown: operation.isPrimaryCountdown)
            context.insert(task); log("Kairos added task", title, explanation)
        case .postpone:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            Planner.postponeWithinDay(task, among: tasks, minutes: operation.value ?? 30)
            log("Kairos postponed", task.title, explanation)
            presentGrace(for: task, trigger: .postponed, revisedStart: revisedStart(for: task))
        case .changeDuration:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            task.estimatedMinutes = operation.value ?? task.estimatedMinutes; log("Kairos changed duration", task.title, explanation)
        case .changePriority:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            task.priority = operation.value ?? task.priority; log("Kairos changed priority", task.title, explanation)
        case .complete:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            task.status = .complete; log("Kairos completed", task.title, explanation)
        case .replan, .none: break
        }
    }
}

private enum TaskReminderKind: Equatable {
    case scheduledStart
    case deadline
}

private struct StartTaskReminderView: View {
    let task: KairosTask
    let kind: TaskReminderKind
    let latestSafeStart: Date?
    let onStart: () -> Void
    let onDismiss: () -> Void
    var onComposeGrace: (() -> Void)?
    @State private var nudge: KairosAgentNudge

    init(task: KairosTask, kind: TaskReminderKind, latestSafeStart: Date?, onStart: @escaping () -> Void, onDismiss: @escaping () -> Void, onComposeGrace: (() -> Void)? = nil) {
        self.task = task
        self.kind = kind
        self.latestSafeStart = latestSafeStart
        self.onStart = onStart
        self.onDismiss = onDismiss
        self.onComposeGrace = onComposeGrace
        let stage: NudgeStage = kind == .deadline
            ? .graceRescue
            : KairosAdvisor.resolveNudgeStage(for: task, latestSafeStart: latestSafeStart)
        _nudge = State(initialValue: KairosAdvisor.generateLocalNudge(for: task, stage: stage))
    }

    private var stageEyebrow: String {
        switch nudge.stage {
        case .transition: "心理预热"
        case .start: "破冰启动"
        case .graceRescue: "无压力降级"
        }
    }

    private var heroIcon: String {
        switch nudge.stage {
        case .transition: "wind"
        case .start: "lightbulb.fill"
        case .graceRescue: "leaf.fill"
        }
    }

    private var timingText: String? {
        switch kind {
        case .scheduledStart:
            return task.scheduledStart.map { "计划开始  \($0.formatted(date: .omitted, time: .shortened))" }
        case .deadline:
            guard let deadline = task.deadline else { return nil }
            if deadline <= .now { return "截止时间已过，先做一个很小的动作就好" }
            let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
            return "距离截止还有 \(minutes) 分钟，步子可以再小一点"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.kairosIndigo, .kairosPurple, .kairosBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.kairosSun.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: 170, y: -280)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 620, height: 620)
                .offset(x: -190, y: 340)

            GeometryReader { geometry in
                Group {
                    if geometry.size.width > geometry.size.height {
                        let actionWidth = min(320, geometry.size.width * 0.34)
                        let messageWidth = min(420, max(240, geometry.size.width - 96 - 40 - actionWidth))
                        HStack(spacing: 40) {
                            reminderMessage(maxWidth: messageWidth, compact: true)
                                .frame(width: messageWidth)
                                .clipped()
                            reminderActions
                                .frame(width: actionWidth)
                        }
                        .padding(.horizontal, 48)
                    } else {
                        let messageWidth = min(420, max(240, geometry.size.width - 48))
                        VStack(spacing: 28) {
                            Spacer(minLength: 28)
                            reminderMessage(maxWidth: messageWidth, compact: false)
                                .frame(width: messageWidth)
                                .clipped()
                            Spacer(minLength: 10)
                            reminderActions
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 36)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .task {
            let refined = await KairosAdvisor.generateNudge(for: task, stage: nudge.stage)
            if refined != nudge { nudge = refined }
        }
    }

    private func reminderMessage(maxWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 16) {
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(Color.kairosSun.opacity(index.isMultiple(of: 2) ? 0.46 : 0.18))
                        .frame(width: 3, height: compact ? 22 : 30)
                        .offset(y: compact ? -52 : -72)
                        .rotationEffect(.degrees(Double(index) * 30))
                }
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: compact ? 88 : 118, height: compact ? 88 : 118)
                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                Image(systemName: heroIcon)
                    .font(.system(size: compact ? 36 : 48, weight: .bold))
                    .foregroundStyle(Color.kairosSun)
                    .symbolEffect(.pulse)
            }
            .frame(width: compact ? 150 : 200, height: compact ? 120 : 168)
            .accessibilityHidden(true)

            Text(stageEyebrow)
                .font(.caption.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(Color.kairosSun)
            Text(nudge.title)
                .font(compact ? .title3.bold() : .title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(task.title)
                .font(.system(size: compact ? 28 : 34, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(width: maxWidth, height: compact ? 70 : 88, alignment: .center)
                .clipped()
            if let timingText {
                Text(timingText)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            microStepCard(compact: compact)
        }
        .frame(width: maxWidth)
        .clipped()
    }

    private func microStepCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text("💡 \(nudge.microStepLabel)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.kairosSun)
            Text(nudge.microStep)
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !nudge.body.isEmpty && !compact {
                Text(nudge.body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.18)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nudge.composedMicroStep)
    }

    private var reminderActions: some View {
        VStack(spacing: 14) {
            Button(nudge.primaryActionTitle, action: onStart)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .padding(.horizontal, 12)
                .background(.white, in: Capsule())
                .foregroundStyle(Color.kairosIndigo)
            Button(nudge.secondaryActionTitle, action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.14), in: Capsule())
                .foregroundStyle(.white)
            if let onComposeGrace {
                Button("需要对外说明？", action: onComposeGrace)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kairosSun)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DeadlineDayCountdown: View {
    let task: KairosTask
    let now: Date

    private var dayText: String {
        guard let deadline = task.deadline else { return "" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if deadline < now { return "已到期" }
        if days == 0 { return "今天截止" }
        return "还剩 \(days) 天"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(dayText)
                .font(.headline.weight(.bold))
            Text(task.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .trailing)
        }
        .foregroundStyle(Color.kairosIndigo.opacity(0.82))
        .accessibilityLabel("\(task.title)，\(dayText)")
    }
}

private struct PersonalHeaderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var motto: String
    @Binding var subgoal: String

    var body: some View {
        NavigationStack {
            Form {
                Section("个人标语或目标") {
                    TextField("例如：拿到理想的工作", text: $motto, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("当前子目标") {
                    TextField("例如：今天完成两道算法题", text: $subgoal, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("编辑首页目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct TaskCard: View {
    let item: PlannedTask
    let isNext: Bool
    let accent: Color
    let onFocus: () -> Void
    let onComplete: () -> Void
    let onPostpone: () -> Void
    let onGrace: (() -> Void)?
    let onDelete: () -> Void
    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var confirmingDelete = false

    var riskColor: Color { switch item.risk { case .safe: .kairosGreen; case .warning: .kairosSun; case .high: .kairosCoral; case .critical: .red } }
    private var revealDistance: CGFloat { -max(-92, min(0, horizontalOffset + dragTranslation)) }
    private var deleteRevealProgress: CGFloat { min(1, revealDistance / 64) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) { confirmingDelete = true } label: {
                VStack(spacing: 7) {
                    Image(systemName: "trash.fill")
                    Text("删除").font(.caption.bold())
                }
                .foregroundStyle(.white)
                .frame(width: 92)
                .frame(maxHeight: .infinity)
                .opacity(deleteRevealProgress)
                .scaleEffect(0.88 + deleteRevealProgress * 0.12)
            }
            .buttonStyle(.plain)
            .background(Color.red.gradient)
            .offset(x: 92 - revealDistance)
            .allowsHitTesting(revealDistance > 40)

            HStack(spacing: 0) {
              RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 6)
              VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) { if isNext { Text("接下来做这个").font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.kairosIndigo) }; Text(item.task.title).font(.title3.bold()); if !item.task.goal.isEmpty { Text(item.task.goal).font(.subheadline).foregroundStyle(.secondary) } }
                    Spacer(); Text(item.risk.displayName).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(riskColor).background(riskColor.opacity(0.1), in: Capsule())
                }
                HStack {
                    Label("\(item.task.estimatedMinutes) 分钟", systemImage: "timer")
                    Spacer()
                    Label("计划 \(item.start.formatted(date: .omitted, time: .shortened))", systemImage: "play.circle")
                    Spacer()
                    if let latest = item.latestSafeStart {
                        Label("最晚 \(latest.formatted(date: .omitted, time: .shortened))", systemImage: "shield")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack { Button("开始专注", action: onFocus).buttonStyle(.borderedProminent); Menu { Button("顺延一项", action: onPostpone); if let onGrace { Button("体面说明", action: onGrace) }; Button("标记完成", action: onComplete) } label: { Image(systemName: "ellipsis.circle").font(.title2) }; Spacer(); NavigationLink { TaskEditor(task: item.task) } label: { Text("编辑").font(.subheadline.bold()) } }
              }.padding(18)
            }
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [.white, accent.opacity(0.07)], startPoint: .leading, endPoint: .trailing))
            .offset(x: -revealDistance)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .updating($dragTranslation) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        state = value.translation.width
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let projected = horizontalOffset + value.predictedEndTranslation.width
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            horizontalOffset = projected < -45 ? -92 : 0
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.18)))
        .shadow(color: accent.opacity(0.10), radius: 14, y: 6)
        .alert("删除任务？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { horizontalOffset = 0 }
            }
            Button("删除", role: .destructive, action: onDelete)
        } message: {
            Text("“\(item.task.title)”删除后无法恢复。")
        }
    }
}
