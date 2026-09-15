import SwiftData
import SwiftUI
import UIKit

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
    @AppStorage("userContextMode") private var userContextModeRaw = UserContextMode.auto.rawValue
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
    @State private var focusGeneration = UUID()
    @State private var graceOffer: GraceMessageOffer?
    @State private var now = Date.now
    @State private var swipedTaskID: UUID?
    @State private var dismissedTimeShortToken: String?
    @State private var refinedRecommendation: KairosRecommendation?

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var timeBias: TimeBiasProfile { TimeBiasReflector.profile(tasks: tasks, events: events) }
    private var plan: [PlannedTask] { Planner.makePlan(tasks: tasks, now: now, bias: timeBias) }
    private var notificationFingerprint: [String] {
        plan.map { item in
            "\(item.task.id)-\(item.task.title)-\(item.task.deadline?.timeIntervalSince1970 ?? 0)-\(item.task.scheduledStart?.timeIntervalSince1970 ?? 0)-\(item.latestSafeStart?.timeIntervalSince1970 ?? 0)-\(item.task.isPrimaryCountdown)-\(item.task.dayOrder)-\(item.task.cognitiveLoad.rawValue)-\(item.task.estimatedMinutes)-\(item.task.timeBiasCalibrationRaw)-\(item.task.repeatsDaily)-\(timeBias.overallRatio)-\(timeBudget.confirmToken)-\(timeBudget.remainingMinutes)"
        }
    }
    private var countdownTask: KairosTask? {
        tasks.first(where: { $0.status != .complete && $0.isPrimaryCountdown && $0.deadline != nil })
            ?? plan.first(where: { $0.task.deadline != nil })?.task
    }
    private var nextTaskBiasInsight: TimeBiasInsight? {
        guard let task = suggestedItem?.task ?? plan.first?.task, timeBias.shouldCalibrate(task.cognitiveLoad) else { return nil }
        return TimeBiasReflector.insight(for: task.cognitiveLoad, tasks: tasks, events: events)
            ?? timeBias.insights.first { $0.isCalibration }
    }
    private var contextMode: UserContextMode {
        UserContextMode(rawValue: userContextModeRaw) ?? .auto
    }
    private var presence: PlacePresence {
        PlaceContext.resolvedPresence(mode: contextMode, current: weather.lastLocation, home: HomeLocation.stored)
    }
    private var timeBudget: TimeBudgetSnapshot {
        TimeBudget.evaluate(plan: plan, now: now, presence: presence)
    }
    private var suggestedItem: PlannedTask? {
        timeBudget.pick
    }
    private var visibleRecommendation: KairosRecommendation? {
        let local = KairosAdvisor.recommendation(for: plan, presence: presence, now: now)
        let rec = (refinedRecommendation?.confirmToken == local?.confirmToken ? refinedRecommendation : nil) ?? local
        guard let rec else { return nil }
        if rec.isTimeShort, dismissedTimeShortToken == rec.confirmToken { return nil }
        return rec
    }
    private var doableNow: [PlannedTask] {
        plan.filter { PlaceContext.shouldHighlightNow($0, presence: presence) }
    }
    private var laterByPlace: [PlannedTask] {
        plan.filter { !PlaceContext.shouldHighlightNow($0, presence: presence) }
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
                        if let insight = nextTaskBiasInsight, let current = suggestedItem ?? plan.first {
                            TimeBiasInsightBubble(
                                text: insight.message(forEstimatedMinutes: current.task.estimatedMinutes),
                                choice: current.task.timeBiasCalibration,
                                onReserve: { acceptTimeBias(for: current.task, insight: insight) },
                                onKeepEstimate: { declineTimeBias(for: current.task) }
                            )
                        }
                        if let recommendation = visibleRecommendation { agentCard(recommendation) }
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
                HabitTracker.handleCompletion(completedTask, in: context, existingTasks: tasks)
                guard saveFocusToCalendar else { return }
                Task {
                    let saved = await calendar.saveFocusSession(task: completedTask, startedAt: startedAt, endedAt: endedAt, focusedSeconds: focusedSeconds)
                    log(saved ? "Added to Calendar" : "Calendar save failed", completedTask.title, saved ? "已把这段真实专注写入日历。" : (calendar.lastError ?? "日历不可用。"))
                    calendarSaveMessage = saved ? "已将“\(completedTask.title)”的专注时段存入 Apple 日历。" : (calendar.lastError ?? "无法写入 Apple 日历。")
                }
            })
            .id(focusGeneration)
            }
            .alert("Apple 日历", isPresented: Binding(get: { calendarSaveMessage != nil }, set: { if !$0 { calendarSaveMessage = nil } })) {
                Button("好") { calendarSaveMessage = nil }
            } message: {
                Text(calendarSaveMessage ?? "")
            }
            .task {
                weather.refresh()
                await notifications.requestPermission()
                await notifications.reschedule(plan: plan, focusTaskID: timeBudget.isShort ? timeBudget.pick?.id : nil)
                WidgetSnapshotStore.update(plan: plan, primaryCountdown: countdownTask)
                try? await Task.sleep(for: .milliseconds(500))
                restorePersistedFocus()
                HabitTracker.refreshBrokenStreaks(in: context)
                if focusTask == nil { checkForStartReminder() }
                if startReminderTask == nil { checkForUrgentTask() }
            }
            .task(id: timeBudget.confirmToken) {
                guard let local = KairosAdvisor.recommendation(for: plan, presence: presence, now: now),
                      local.isTimeShort,
                      let pick = timeBudget.pick else {
                    refinedRecommendation = nil
                    return
                }
                refinedRecommendation = await KairosAdvisor.refineRecommendation(
                    local,
                    pick: pick,
                    budget: timeBudget
                )
            }
            .onChange(of: notificationFingerprint) { _, _ in
                WidgetSnapshotStore.update(plan: plan, primaryCountdown: countdownTask)
                Task { await notifications.reschedule(plan: plan, focusTaskID: timeBudget.isShort ? timeBudget.pick?.id : nil) }
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
                    weather.refresh()
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
            Text(recommendation.eyebrow)
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(recommendation.isTimeShort ? Color.kairosCoral : Color.kairosPurple)
            Text(recommendation.headline).font(.title2.bold())
            Text(recommendation.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(recommendation.consequence, systemImage: "arrow.triangle.branch").font(.subheadline.weight(.medium)).foregroundStyle(Color.kairosCoral)
            if let current = plan.first(where: { $0.task.id == recommendation.pickID }) ?? suggestedItem ?? plan.first {
                if !recommendation.confirmPrompt.isEmpty {
                    Text(recommendation.confirmPrompt)
                        .font(.subheadline.bold())
                }
                HStack(spacing: 8) {
                    Button(recommendation.primaryActionTitle) {
                        dismissedTimeShortToken = recommendation.confirmToken
                        startFocus(current.task, detail: recommendation.isTimeShort
                            ? "User confirmed the time-budget priority recommendation."
                            : "Kairos recommended starting now.")
                    }
                        .buttonStyle(.borderedProminent)
                    if recommendation.isTimeShort {
                        Button(recommendation.secondaryActionTitle) {
                            dismissedTimeShortToken = recommendation.confirmToken
                        }
                        .buttonStyle(.bordered)
                    } else if let next = plan.first(where: { $0.id != current.id }),
                              Planner.isScheduledOnSameDay(current.task, next.task, now: now) {
                        Button(recommendation.secondaryActionTitle) { postponeCurrent(current.task, next: next.task) }
                            .buttonStyle(.bordered)
                    }
                    if !recommendation.isTimeShort {
                        Button("结束任务") { complete(current.task) }
                            .buttonStyle(.bordered)
                    }
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
        HStack(alignment: .top, spacing: 12) {
            ContextStatusCapsule(
                presence: presence,
                mode: contextMode,
                weatherSummary: contextWeatherSummary,
                weatherSymbol: weather.symbol,
                onSelect: selectContextMode,
                onOpenHomeSettings: { showingSettings = true }
            )
            Spacer(minLength: 10)
            if let countdownTask {
                DeadlineDayCountdown(task: countdownTask, now: now)
            }
        }
    }

    private var contextWeatherSummary: String {
        var parts: [String] = []
        if let temperature = weather.temperature { parts.append(temperature) }
        if !weather.condition.contains("无法") { parts.append(weather.condition) }
        return parts.joined(separator: " ")
    }

    private func selectContextMode(_ mode: UserContextMode) {
        guard mode.rawValue != userContextModeRaw else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        userContextModeRaw = mode.rawValue
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
        VStack(alignment: .leading, spacing: 16) {
            if !doableNow.isEmpty {
                if presence != .unknown || !laterByPlace.isEmpty {
                    Text("此刻能做").font(.caption.bold()).foregroundStyle(Color.kairosIndigo).tracking(1)
                }
                ForEach(Array(doableNow.enumerated()), id: \.element.id) { index, item in
                    taskCard(item, accentIndex: index, deferred: false)
                }
            }
            if !laterByPlace.isEmpty {
                Text(PlaceContext.laterSectionTitle(presence: presence))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1)
                    .padding(.top, 4)
                ForEach(Array(laterByPlace.enumerated()), id: \.element.id) { index, item in
                    taskCard(item, accentIndex: doableNow.count + index, deferred: true)
                }
            }
        }
    }

    private func taskCard(_ item: PlannedTask, accentIndex: Int, deferred: Bool) -> some View {
        TaskCard(
            item: item,
            isNext: item.id == suggestedItem?.id,
            accent: KairosTheme.accents[accentIndex % KairosTheme.accents.count],
            swipedTaskID: $swipedTaskID,
            placeNote: PlaceContext.availabilityNote(for: item, presence: presence),
            isDeferred: deferred,
            onFocus: { startFocus(item.task, detail: "\(item.task.estimatedMinutes) minute countdown started.") },
            onComplete: { markTaskComplete(item.task, detail: "Task marked complete.") },
            onPostpone: {
                Planner.postponeWithinDay(item.task, among: tasks, minutes: 30, now: now)
                log("Postponed", item.task.title, "Moved later among tasks scheduled for the same day.")
                presentGrace(for: item.task, trigger: .postponed, revisedStart: revisedStart(for: item.task))
            },
            onGrace: (item.risk == .high || item.risk == .critical) ? { presentGrace(for: item.task, trigger: graceTrigger(for: item)) } : nil,
            onDelete: {
                log("Deleted", item.task.title, "Task deleted after confirmation.")
                context.delete(item.task)
            }
        )
        .opacity(deferred ? 0.62 : 1)
    }

    private func log(_ action: String, _ task: String, _ detail: String) { context.insert(ActivityEvent(action: action, taskTitle: task, detail: detail)) }

    private func markTaskComplete(_ task: KairosTask, detail: String) {
        task.status = .complete
        log("Completed", task.title, detail)
        HabitTracker.handleCompletion(task, in: context, existingTasks: tasks)
    }

    private func startFocus(_ task: KairosTask, detail: String) {
        FocusSessionStore.clear()
        restoredFocus = nil
        focusGeneration = UUID()
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
        focusGeneration = UUID()
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
                if timeBudget.isShort, task.id != timeBudget.pick?.task.id { return false }
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
                if timeBudget.isShort, task.id != timeBudget.pick?.task.id { return false }
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
        markTaskComplete(task, detail: "Task ended from the Kairos recommendation.")
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
            let guessed = TaskContextGuess.place(from: title)
            let load = TaskContextGuess.cognitiveLoad(from: title)
            let task = KairosTask(title: title, deadline: operation.deadline, estimatedMinutes: operation.value ?? 30, priority: 3, cognitiveLoad: load, deadlineType: operation.deadline == nil ? .none : .soft, isPrimaryCountdown: operation.isPrimaryCountdown, place: guessed)
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
            markTaskComplete(task, detail: explanation)
        case .startFocus:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            startFocus(task, detail: explanation)
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

private struct ContextStatusCapsule: View {
    let presence: PlacePresence
    let mode: UserContextMode
    let weatherSummary: String
    let weatherSymbol: String
    let onSelect: (UserContextMode) -> Void
    let onOpenHomeSettings: () -> Void

    private var sceneTitle: String {
        switch presence {
        case .atHome: "在家"
        case .away: "外出"
        case .unknown: mode == .auto ? "自动" : mode.menuTitle
        }
    }

    var body: some View {
        Menu {
            Picker("情境", selection: Binding(
                get: { mode },
                set: onSelect
            )) {
                Label("在家", systemImage: "house.fill").tag(UserContextMode.home)
                Label("外出", systemImage: "location.fill").tag(UserContextMode.away)
            }
            Divider()
            Button {
                onSelect(.auto)
            } label: {
                Label("自动跟随定位", systemImage: "sparkles")
            }
            if HomeLocation.stored == nil {
                Button(action: onOpenHomeSettings) {
                    Label("设置家庭地址", systemImage: "house.badge.plus")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(sceneTitle)
                        .font(.headline.weight(.bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.kairosIndigo.opacity(0.55))
                }
                HStack(spacing: 4) {
                    Image(systemName: weatherSymbol)
                        .font(.caption)
                        .symbolRenderingMode(.multicolor)
                    Text(weatherSummary.isEmpty ? weatherFallback : weatherSummary)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.kairosIndigo.opacity(0.82))
            .frame(maxWidth: 180, alignment: .leading)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("当前情境\(sceneTitle)\(weatherSummary.isEmpty ? "" : "，\(weatherSummary)")")
        .accessibilityHint("切换在家或外出")
    }

    private var weatherFallback: String { "天气" }
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
    @Binding var swipedTaskID: UUID?
    var placeNote: String = TaskPlace.anywhere.displayName
    var isDeferred = false
    let onFocus: () -> Void
    let onComplete: () -> Void
    let onPostpone: () -> Void
    let onGrace: (() -> Void)?
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var axis: Axis?
    @State private var confirmingDelete = false

    private let actionWidth: CGFloat = 80
    private let snap = Animation.interpolatingSpring(stiffness: 420, damping: 36)
    var riskColor: Color { switch item.risk { case .safe: .kairosGreen; case .warning: .kairosSun; case .high: .kairosCoral; case .critical: .red } }
    private var revealed: CGFloat { max(0, -offset) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) { confirmingDelete = true } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("删除").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: max(actionWidth, revealed))
                .frame(maxHeight: .infinity)
                .background(Color.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除\(item.task.title)")

            cardContent
                .offset(x: offset)
                .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.18)))
        .shadow(color: accent.opacity(offset == 0 ? 0.10 : 0.04), radius: offset == 0 ? 14 : 4, y: offset == 0 ? 6 : 1)
        .onChange(of: swipedTaskID) { _, id in
            guard id != item.id, offset != 0 else { return }
            withAnimation(snap) { offset = 0 }
        }
        .alert("删除任务？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) { close() }
            Button("删除", role: .destructive, action: onDelete)
        } message: {
            Text("“\(item.task.title)”删除后无法恢复。")
        }
    }

    private var cardContent: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 6)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        if isNext { Text("接下来做这个").font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.kairosIndigo) }
                        Text(item.task.title).font(.title3.bold())
                        if !item.task.goal.isEmpty { Text(item.task.goal).font(.subheadline).foregroundStyle(.secondary) }
                        Label(placeNote, systemImage: item.task.place.icon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isDeferred ? Color.kairosCoral : Color.kairosIndigo.opacity(0.8))
                    }
                    Spacer()
                    Text(item.risk.displayName).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(riskColor).background(riskColor.opacity(0.1), in: Capsule())
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
                HStack {
                    Button("开始专注", action: onFocus).buttonStyle(.borderedProminent)
                    Menu {
                        Button("顺延一项", action: onPostpone)
                        if let onGrace { Button("体面说明", action: onGrace) }
                        Button("标记完成", action: onComplete)
                    } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                    Spacer()
                    NavigationLink { TaskEditor(task: item.task) } label: { Text("编辑").font(.subheadline.bold()) }
                }
            }.padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.overlay(accent.opacity(0.07)))
        .overlay {
            if offset != 0 {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if axis == nil {
                    guard abs(dx) > 8 || abs(dy) > 8 else { return }
                    axis = abs(dx) > abs(dy) ? .horizontal : .vertical
                    if axis == .horizontal {
                        startOffset = offset
                        swipedTaskID = item.id
                    }
                }
                guard axis == .horizontal else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    offset = rubberBand(startOffset + dx)
                }
            }
            .onEnded { value in
                let wasHorizontal = axis == .horizontal
                axis = nil
                guard wasHorizontal else { return }
                let predicted = startOffset + value.predictedEndTranslation.width
                let shouldOpen = predicted < -actionWidth * 0.45
                withAnimation(snap) {
                    offset = shouldOpen ? -actionWidth : 0
                }
                if shouldOpen {
                    swipedTaskID = item.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else if swipedTaskID == item.id {
                    swipedTaskID = nil
                }
            }
    }

    private func rubberBand(_ proposed: CGFloat) -> CGFloat {
        if proposed > 0 { return proposed * 0.18 }
        let overflow = -proposed - actionWidth
        if overflow > 0 { return -(actionWidth + overflow * 0.28) }
        return proposed
    }

    private func close() {
        withAnimation(snap) { offset = 0 }
        if swipedTaskID == item.id { swipedTaskID = nil }
    }
}
