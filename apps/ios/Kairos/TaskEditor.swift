import SwiftData
import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \KairosTask.createdAt) private var allTasks: [KairosTask]
    var task: KairosTask?
    @State private var title = ""
    @State private var goal = ""
    @State private var hasDeadline = true
    @State private var deadline = Date.now.addingTimeInterval(3_600)
    @State private var hasScheduledStart = false
    @State private var scheduledStart = Date.now.addingTimeInterval(300)
    @State private var minutes = 30
    @State private var priority = 3
    @State private var load = CognitiveLoad.medium
    @State private var deadlineType = DeadlineType.soft
    @State private var interruptible = true
    @State private var isPrimaryCountdown = false

    var body: some View {
        Form {
                Section("What needs doing?") { TextField("Task title", text: $title); TextField("Goal (optional)", text: $goal) }
                Section("Time") {
                    Toggle("设置开始时间", isOn: $hasScheduledStart)
                    if hasScheduledStart {
                        DatePicker("开始", selection: $scheduledStart, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        Text("到达开始时间时，Kairos 会提醒你该做这项任务。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Has a deadline", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Deadline", selection: $deadline, in: Date.now..., displayedComponents: [.date, .hourAndMinute]); Toggle("设为首页主要倒数日", isOn: $isPrimaryCountdown); Picker("Deadline type", selection: $deadlineType) { ForEach(DeadlineType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } } }
                    HStack {
                        Text("Estimated duration")
                        Spacer()
                        TextField("30", value: $minutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.kairosBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                        Text("min").foregroundStyle(.secondary)
                    }
                    if !(5...720).contains(minutes) { Text("Enter a duration from 5 to 720 minutes.").font(.caption).foregroundStyle(.red) }
                }
                Section("Effort") {
                    Picker("Priority", selection: $priority) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }
                    Picker("Cognitive load", selection: $load) { ForEach(CognitiveLoad.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    Toggle("Can be interrupted", isOn: $interruptible)
                }
        }
        .navigationTitle(task == nil ? "New task" : "Edit task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if task == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !(5...720).contains(minutes)) }
        }
        .onAppear {
            guard let task else { return }
            title = task.title; goal = task.goal; hasDeadline = task.deadline != nil; deadline = task.deadline ?? deadline
            hasScheduledStart = task.scheduledStart != nil; scheduledStart = task.scheduledStart ?? scheduledStart
            minutes = task.estimatedMinutes; priority = task.priority; load = task.cognitiveLoad
            deadlineType = task.deadlineType; interruptible = task.isInterruptible
            isPrimaryCountdown = task.isPrimaryCountdown
        }
    }

    private func save() {
        if hasDeadline && isPrimaryCountdown {
            for existing in allTasks where existing.id != task?.id { existing.isPrimaryCountdown = false }
        }
        if let task {
            task.title = title; task.goal = goal; task.deadline = hasDeadline ? deadline : nil; task.estimatedMinutes = minutes
            task.scheduledStart = hasScheduledStart ? scheduledStart : nil
            task.priority = priority; task.cognitiveLoad = load; task.deadlineType = hasDeadline ? deadlineType : .none; task.isInterruptible = interruptible
            task.isPrimaryCountdown = hasDeadline && isPrimaryCountdown
        } else {
            context.insert(KairosTask(title: title, goal: goal, deadline: hasDeadline ? deadline : nil, scheduledStart: hasScheduledStart ? scheduledStart : nil, estimatedMinutes: minutes, priority: priority, cognitiveLoad: load, isInterruptible: interruptible, deadlineType: hasDeadline ? deadlineType : .none, isPrimaryCountdown: hasDeadline && isPrimaryCountdown))
            context.insert(ActivityEvent(action: "Task created", taskTitle: title, detail: "Estimated at \(minutes) minutes."))
        }
        dismiss()
    }
}

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.title) private var routines: [Routine]
    @State private var showingNewHabit = false

    private var completedToday: Int { routines.filter(\.isDoneToday).count }

    var body: some View {
        ZStack {
            KairosTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("习惯记录")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                        Text("今天完成 \(completedToday) / \(routines.count)")
                            .foregroundStyle(.secondary)
                    }

                    if routines.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.kairosPurple)
                            Text("还没有习惯").font(.headline)
                            Text("添加 LeetCode、运动或模拟面试，Kairos 会记录你的连续天数。")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            Button("添加第一个习惯") { showingNewHabit = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 9))
                    } else {
                        ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                            habitCard(routine, accent: KairosTheme.accents[index % KairosTheme.accents.count])
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("习惯")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewHabit = true } label: {
                    Label("添加习惯", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewHabit) { NewHabitView() }
    }

    private func habitCard(_ routine: Routine, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title).font(.title3.bold())
                    Text("每天 \(routine.targetMinutes) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("删除习惯", role: .destructive) { context.delete(routine) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                Image(systemName: routine.streak > 0 ? "flame.fill" : "flame")
                    .font(.title2)
                    .foregroundStyle(routine.streak > 0 ? accent : .secondary)
                Text("\(routine.streak)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Text("天连续")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(routine.isDoneToday ? "今天已完成" : "今天待完成", systemImage: routine.isDoneToday ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(routine.isDoneToday ? accent : .secondary)
            }

            Button {
                completeToday(routine)
            } label: {
                Label(routine.isDoneToday ? "今日已完成" : "完成今日打卡", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(routine.isDoneToday)
        }
        .padding(18)
        .background(LinearGradient(colors: [.white.opacity(0.92), accent.opacity(0.08)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.18)))
    }

    private func completeToday(_ routine: Routine) {
        guard !routine.isDoneToday else { return }
        let calendar = Calendar.current
        if let lastCompletedDay = routine.lastCompletedDay, calendar.isDateInYesterday(lastCompletedDay) {
            routine.streak += 1
        } else {
            routine.streak = 1
        }
        routine.lastCompletedDay = .now
        context.insert(ActivityEvent(action: "Routine completed", taskTitle: routine.title, detail: "\(routine.streak) day streak protected."))
    }
}

private struct NewHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var minutes = 20

    var body: some View {
        NavigationStack {
            Form {
                Section("习惯") {
                    TextField("LeetCode、运动、模拟面试……", text: $title)
                    Stepper("每天 \(minutes) 分钟", value: $minutes, in: 5...180, step: 5)
                }
            }
            .navigationTitle("添加习惯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        context.insert(Routine(title: cleanTitle, targetMinutes: minutes))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
