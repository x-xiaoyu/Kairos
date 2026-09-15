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
    @AppStorage("personalMotto") private var personalMotto = "What matters now"
    @AppStorage("personalSubgoal") private var personalSubgoal = "Your safest next step is already at the top."
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
    @State private var now = Date.now

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var plan: [PlannedTask] { Planner.makePlan(tasks: tasks, now: now) }
    private var notificationFingerprint: [String] {
        plan.map { item in
            "\(item.task.id)-\(item.task.title)-\(item.task.deadline?.timeIntervalSince1970 ?? 0)-\(item.task.scheduledStart?.timeIntervalSince1970 ?? 0)-\(item.latestSafeStart?.timeIntervalSince1970 ?? 0)-\(item.task.isPrimaryCountdown)-\(item.task.dayOrder)"
        }
    }
    private var countdownTask: KairosTask? {
        tasks.first(where: { $0.status != .complete && $0.isPrimaryCountdown && $0.deadline != nil })
            ?? plan.first(where: { $0.task.deadline != nil })?.task
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
                        if let recommendation = KairosAdvisor.recommendation(for: plan) { agentCard(recommendation) }
                        if plan.isEmpty { emptyState } else { planList }
                    }.padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
            .sheet(isPresented: $showingNewTask) { NavigationStack { TaskEditor() } }
            .navigationDestination(isPresented: $showingReview) { DayReviewView(events: events, completed: tasks.filter { $0.status == .complete }) }
            .navigationDestination(isPresented: $showingRoutines) { HabitsView() }
            .navigationDestination(isPresented: $showingSettings) { KairosSettingsView() }
            .navigationDestination(isPresented: $showingAgent) { AskKairosView(tasks: tasks, onApply: applyAgentProposal) }
            .sheet(isPresented: $showingHeaderEditor) {
                PersonalHeaderEditor(motto: $personalMotto, subgoal: $personalSubgoal)
            }
            .fullScreenCover(item: $startReminderTask) { task in
                StartTaskReminderView(
                    task: task,
                    kind: .scheduledStart,
                    onStart: { beginFromStartReminder(task) },
                    onDismiss: { dismissStartReminder(task) }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $urgentTask) { task in
                StartTaskReminderView(
                    task: task,
                    kind: .deadline,
                    onStart: { beginFromUrgentReminder(task) },
                    onDismiss: { urgentTask = nil }
                )
                .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $focusTask) { task in FocusView(task: task, availableTasks: tasks, log: { action, focusedTask, detail in
                log(action, focusedTask.title, detail)
            }, onComplete: { completedTask, startedAt, endedAt, focusedSeconds in
                guard saveFocusToCalendar else { return }
                Task {
                    let saved = await calendar.saveFocusSession(task: completedTask, startedAt: startedAt, endedAt: endedAt, focusedSeconds: focusedSeconds)
                    log(saved ? "Added to Calendar" : "Calendar save failed", completedTask.title, saved ? "The completed focus period was saved in the Kairos calendar." : (calendar.lastError ?? "Calendar was unavailable."))
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
                checkForStartReminder()
                if startReminderTask == nil { checkForUrgentTask() }
            }
            .onChange(of: notificationFingerprint) { _, _ in
                WidgetSnapshotStore.update(plan: plan, primaryCountdown: countdownTask)
                Task { await notifications.reschedule(plan: plan) }
                checkForStartReminder()
            }
            .onChange(of: weatherUnit) { _, _ in weather.refresh() }
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
            .accessibilityLabel("\(weather.condition) in \(weather.locationName)\(weather.temperature.map { ", \($0)" } ?? ""). Refresh weather")

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
            Text("Your day is open").font(.title2.bold())
            Text("Create your first task with its deadline and expected duration. Kairos will tell you when it’s time to begin.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button { showingAgent = true } label: { Label("告诉 Kairos", systemImage: "message.fill") }.buttonStyle(.borderedProminent)
                Button("Add task manually") { showingNewTask = true }.buttonStyle(.bordered)
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
                }, onDelete: {
                    log("Deleted", item.task.title, "Task deleted after confirmation.")
                    context.delete(item.task)
                })
            }
        }
    }

    private func log(_ action: String, _ task: String, _ detail: String) { context.insert(ActivityEvent(action: action, taskTitle: task, detail: detail)) }

    private func startFocus(_ task: KairosTask, detail: String) {
        log("Focus started", task.title, detail)
        focusTask = task
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
            let title = operation.taskTitle ?? "New task"
            if operation.isPrimaryCountdown {
                for existing in tasks { existing.isPrimaryCountdown = false }
            }
            let task = KairosTask(title: title, deadline: operation.deadline, estimatedMinutes: operation.value ?? 30, priority: 3, cognitiveLoad: .medium, deadlineType: operation.deadline == nil ? .none : .soft, isPrimaryCountdown: operation.isPrimaryCountdown)
            context.insert(task); log("Kairos added task", title, explanation)
        case .postpone:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            Planner.postponeWithinDay(task, among: tasks, minutes: operation.value ?? 30)
            log("Kairos postponed", task.title, explanation)
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
    let onStart: () -> Void
    let onDismiss: () -> Void

    private var heading: String {
        guard kind == .deadline, let deadline = task.deadline else { return "现在该做" }
        if deadline <= .now { return "任务已经到期" }
        let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
        return minutes <= 10 ? "只剩最后 \(minutes) 分钟" : "截止时间临近"
    }

    private var timingText: String? {
        switch kind {
        case .scheduledStart:
            return task.scheduledStart.map { "计划开始时间  \($0.formatted(date: .abbreviated, time: .shortened))" }
        case .deadline:
            guard let deadline = task.deadline else { return nil }
            if deadline <= .now { return "已经超过截止时间" }
            let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
            return "距离截止还有 \(minutes) 分钟"
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
                        VStack(spacing: 46) {
                            Spacer(minLength: 36)
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
    }

    private func reminderMessage(maxWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 18) {
            ZStack {
                ForEach(0..<24, id: \.self) { index in
                    Capsule()
                        .fill(Color.kairosSun.opacity(index.isMultiple(of: 2) ? 0.72 : 0.28))
                        .frame(
                            width: index.isMultiple(of: 2) ? (compact ? 4 : 5) : 3,
                            height: index.isMultiple(of: 2) ? (compact ? 38 : 54) : (compact ? 24 : 34)
                        )
                        .offset(y: compact ? -65 : -94)
                        .rotationEffect(.degrees(Double(index) * 15))
                }
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: compact ? 102 : 144, height: compact ? 102 : 144)
                    .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                Image(systemName: "megaphone.fill")
                    .font(.system(size: compact ? 50 : 72, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
            }
            .frame(width: compact ? 180 : 250, height: compact ? 150 : 220)
            .accessibilityHidden(true)

            Text(heading)
                .font(compact ? .subheadline.bold() : .headline)
                .tracking(3)
                .foregroundStyle(Color.kairosSun)
            Text(task.title)
                .font(.system(size: compact ? 34 : 40, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(width: maxWidth, height: compact ? 84 : 104, alignment: .center)
                .clipped()
            if let timingText {
                Text(timingText)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(kind == .deadline ? "现在开始，先完成最重要的一步。" : "先开始这一项，其他事情稍后再处理。")
                .font(compact ? .caption : .body)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : 2)
        }
        .frame(width: maxWidth)
        .clipped()
    }

    private var reminderActions: some View {
        VStack(spacing: 14) {
            Button("立即开始专注", action: onStart)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(.white, in: Capsule())
                .foregroundStyle(Color.kairosIndigo)
            Button("关闭本次提醒", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white.opacity(0.14), in: Capsule())
                .foregroundStyle(.white)
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
                    VStack(alignment: .leading, spacing: 5) { if isNext { Text("DO THIS NEXT").font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.kairosIndigo) }; Text(item.task.title).font(.title3.bold()); if !item.task.goal.isEmpty { Text(item.task.goal).font(.subheadline).foregroundStyle(.secondary) } }
                    Spacer(); Text(item.risk.rawValue.uppercased()).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(riskColor).background(riskColor.opacity(0.1), in: Capsule())
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
                HStack { Button("Start focus", action: onFocus).buttonStyle(.borderedProminent); Menu { Button("顺延一项", action: onPostpone); Button("标记完成", action: onComplete) } label: { Image(systemName: "ellipsis.circle").font(.title2) }; Spacer(); NavigationLink { TaskEditor(task: item.task) } label: { Text("Edit").font(.subheadline.bold()) } }
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
