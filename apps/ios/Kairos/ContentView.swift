import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
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
    @State private var focusTask: KairosTask?
    @State private var now = Date.now

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var plan: [PlannedTask] { Planner.makePlan(tasks: tasks, now: now) }
    private var countdownTask: KairosTask? { plan.first(where: { $0.task.deadline != nil })?.task }

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
            .sheet(isPresented: $showingNewTask) { TaskEditor() }
            .sheet(isPresented: $showingReview) { DayReviewView(events: events, completed: tasks.filter { $0.status == .complete }) }
            .navigationDestination(isPresented: $showingRoutines) { HabitsView() }
            .sheet(isPresented: $showingSettings) { KairosSettingsView() }
            .sheet(isPresented: $showingAgent) { AskKairosView(tasks: tasks, onApply: applyAgentProposal) }
            .sheet(isPresented: $showingHeaderEditor) {
                PersonalHeaderEditor(motto: $personalMotto, subgoal: $personalSubgoal)
            }
            .fullScreenCover(item: $focusTask) { task in FocusView(task: task, log: { action, detail in log(action, task.title, detail) }, onComplete: { startedAt, endedAt, focusedSeconds in
                guard saveFocusToCalendar else { return }
                Task {
                    let saved = await calendar.saveFocusSession(task: task, startedAt: startedAt, endedAt: endedAt, focusedSeconds: focusedSeconds)
                    log(saved ? "Added to Calendar" : "Calendar save failed", task.title, saved ? "The completed focus period was saved in the Kairos calendar." : (calendar.lastError ?? "Calendar was unavailable."))
                }
            }) }
            .task { weather.refresh(); await notifications.requestPermission(); await notifications.reschedule(plan: plan) }
            .onChange(of: plan.map(\.task.id)) { _, _ in Task { await notifications.reschedule(plan: plan) } }
            .onChange(of: weatherUnit) { _, _ in weather.refresh() }
            .onReceive(clock) { now = $0 }
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
                    if plan.count > 1 {
                        Button("开始下一项任务") { postponeAndStartNext(current: current.task, next: plan[1].task) }
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
                    item.task.priority = max(1, item.task.priority - 1); log("Postponed", item.task.title, "Priority lowered so the plan can adapt.")
                })
            }
        }
    }

    private func log(_ action: String, _ task: String, _ detail: String) { context.insert(ActivityEvent(action: action, taskTitle: task, detail: detail)) }

    private func startFocus(_ task: KairosTask, detail: String) {
        log("Focus started", task.title, detail)
        focusTask = task
    }

    private func postponeAndStartNext(current: KairosTask, next: KairosTask) {
        current.availableAfter = now.addingTimeInterval(30 * 60)
        log("Postponed", current.title, "Postponed 30 minutes to start the next task.")
        startFocus(next, detail: "Started after postponing \(current.title).")
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
            let task = KairosTask(title: title, deadline: operation.deadline, estimatedMinutes: operation.value ?? 30, priority: 3, cognitiveLoad: .medium, deadlineType: operation.deadline == nil ? .none : .soft)
            context.insert(task); log("Kairos added task", title, explanation)
        case .postpone:
            guard let task = tasks.first(where: { $0.id == operation.taskID }) else { return }
            task.availableAfter = Date.now.addingTimeInterval(Double((operation.value ?? 30) * 60)); log("Kairos postponed", task.title, explanation)
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

    var riskColor: Color { switch item.risk { case .safe: .kairosGreen; case .warning: .kairosSun; case .high: .kairosCoral; case .critical: .red } }

    var body: some View {
        HStack(spacing: 0) {
          RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 6)
          VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) { if isNext { Text("DO THIS NEXT").font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.kairosIndigo) }; Text(item.task.title).font(.title3.bold()); if !item.task.goal.isEmpty { Text(item.task.goal).font(.subheadline).foregroundStyle(.secondary) } }
                Spacer(); Text(item.risk.rawValue.uppercased()).font(.caption2.bold()).padding(.horizontal, 9).padding(.vertical, 5).foregroundStyle(riskColor).background(riskColor.opacity(0.1), in: Capsule())
            }
            HStack { Label("\(item.task.estimatedMinutes)m", systemImage: "timer"); Spacer(); Label(item.start.formatted(date: .omitted, time: .shortened), systemImage: "play.circle"); Spacer(); if let latest = item.latestSafeStart { Label("Safe by \(latest.formatted(date: .omitted, time: .shortened))", systemImage: "shield") } }.font(.caption).foregroundStyle(.secondary)
            HStack { Button("Start focus", action: onFocus).buttonStyle(.borderedProminent); Menu { Button("Postpone", action: onPostpone); Button("Mark complete", action: onComplete) } label: { Image(systemName: "ellipsis.circle").font(.title2) }; Spacer(); NavigationLink { TaskEditor(task: item.task) } label: { Text("Edit").font(.subheadline.bold()) } }
          }.padding(18)
        }.background(LinearGradient(colors: [.white, accent.opacity(0.07)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.18))).shadow(color: accent.opacity(0.10), radius: 14, y: 6)
    }
}
