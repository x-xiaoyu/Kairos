import SwiftData
import SwiftUI

struct DayReviewView: View {
    @Environment(\.modelContext) private var context
    let events: [ActivityEvent]
    let completed: [KairosTask]
    var tasks: [KairosTask] = []
    @State private var showingCompleted = false
    @State private var readdedTitle: String?

    private var today: [ActivityEvent] { events.filter { Calendar.current.isDateInToday($0.timestamp) } }
    private var timeBias: TimeBiasProfile { TimeBiasReflector.profile(tasks: tasks.isEmpty ? completed : tasks, events: events) }
    private var actualFocusedMinutes: Int {
        TimeBiasReflector.samples(from: tasks.isEmpty ? completed : tasks, events: events)
            .filter { Calendar.current.isDateInToday($0.completedAt) }
            .reduce(0) { $0 + $1.actualMinutes }
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { Text("今日节奏").font(.caption2.bold()).tracking(1.5).foregroundStyle(Color.kairosPurple); Text("回顾这一天").font(.system(size: 36, weight: .bold, design: .serif)); Text("按发生顺序看看你做了什么。").foregroundStyle(.secondary) }
                    HStack { completedStat; stat("\(actualFocusedMinutes) 分钟", "所用时间"); stat("\(today.filter { $0.action.contains("Focus") }.count)", "专注事件") }
                    if let insight = timeBias.insights.first {
                        timeBiasCard(insight)
                    }
                    if showingCompleted { completedList } else { timeline(today, emptyTitle: "今天还没有记录") }
                }.padding(20)
            }
            .background(KairosTheme.background)
            .navigationTitle("回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .alert("已加入待办", isPresented: Binding(get: { readdedTitle != nil }, set: { if !$0 { readdedTitle = nil } })) {
                Button("好") { readdedTitle = nil }
            } message: {
                Text("“\(readdedTitle ?? "")”已经再次出现在首页。")
            }
    }

    private func stat(_ value: String, _ label: String) -> some View { VStack(alignment: .leading) { Text(value).font(.title2.bold()).foregroundStyle(Color.kairosPurple); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(LinearGradient(colors: [.white, .kairosPurple.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6)) }

    private func timeBiasCard(_ insight: TimeBiasInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("时间盲症校准").font(.caption.bold()).foregroundStyle(Color.kairosIndigo)
            Text(insight.recommendationText).font(.subheadline.weight(.medium))
            if insight.isCalibration {
                Text("排期已用校准后的时长计算最晚开始时间；若你更想按自己填的数字走，预警会更灵敏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if insight.averageUnderestimateMinutes != 0 {
                Text("已根据最近 \(insight.sampleCount) 次完成记录，把排期缓冲调整为约 \(Int((insight.biasRatio * 100).rounded()))%。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [.white, Color.kairosSun.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kairosSun.opacity(0.28)))
    }

    private var completedStat: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { showingCompleted.toggle() } } label: {
            VStack(alignment: .leading) {
                HStack { Text("\(completed.count)").font(.title2.bold()); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
                Text("已完成").font(.caption)
            }.foregroundStyle(Color.kairosPurple).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(LinearGradient(colors: [.white, .kairosPurple.opacity(showingCompleted ? 0.24 : 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.kairosPurple.opacity(showingCompleted ? 0.75 : 0.18), lineWidth: showingCompleted ? 2 : 1))
        }.buttonStyle(.plain).accessibilityHint("查看全部已完成任务")
    }

    private func timeline(_ items: [ActivityEvent], emptyTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty { ContentUnavailableView(emptyTitle, systemImage: "clock", description: Text("你的操作会按准确时间出现在这里。")) }
            ForEach(items) { event in
                HStack(alignment: .top, spacing: 14) {
                    Text(event.timestamp.formatted(date: .omitted, time: .shortened)).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Image(systemName: event.action == "Completed" ? "checkmark.circle.fill" : "circle.fill").foregroundStyle(event.action == "Completed" ? Color.kairosGreen : Color.kairosBlue).font(.caption).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) { Text(event.action.uppercased()).font(.caption2.bold()).foregroundStyle(event.action == "Completed" ? Color.kairosGreen : Color.kairosBlue); Text(event.taskTitle).font(.headline); Text(event.detail).font(.caption).foregroundStyle(.secondary) }.padding(.bottom, 24)
                }
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 8))
    }

    private var completedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("已完成的任务").font(.headline); Spacer(); Button("全部动态") { withAnimation { showingCompleted = false } }.font(.caption.bold()) }
            if completed.isEmpty { ContentUnavailableView("还没有完成的任务", systemImage: "checkmark.circle", description: Text("完成任务后会出现在这里。")) }
            ForEach(completed.sorted { completionDate(for: $0) > completionDate(for: $1) }) { task in
                Button { readd(task) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kairosGreen); Text(task.title).font(.headline).foregroundStyle(.primary); Spacer(); Text(completionDate(for: task).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                        if !task.goal.isEmpty { Text(task.goal).font(.subheadline).foregroundStyle(.secondary) }
                        HStack {
                            Label(actualDurationLabel(for: task), systemImage: "timer")
                            Text("优先级 \(task.priority)")
                            Spacer()
                            Text("再做一次").font(.caption.bold()).foregroundStyle(Color.kairosIndigo)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(14).background(Color.kairosGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityHint("再次添加这个任务到待办")
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 8)).transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func completionDate(for task: KairosTask) -> Date {
        events.first(where: { $0.action == "Completed" && $0.taskTitle == task.title })?.timestamp ?? task.createdAt
    }

    private func actualDurationLabel(for task: KairosTask) -> String {
        if let minutes = actualMinutes(for: task) {
            return "实际 \(minutes) 分钟"
        }
        return "未记录实际用时"
    }

    private func actualMinutes(for task: KairosTask) -> Int? {
        TimeBiasReflector.samples(from: tasks.isEmpty ? completed : tasks, events: events)
            .filter { $0.taskTitle == task.title }
            .sorted { $0.completedAt > $1.completedAt }
            .first?.actualMinutes
    }

    private func readd(_ task: KairosTask) {
        let copy = task.duplicatedAsTodo(scheduledStart: nil, keepRepeat: task.repeatsDaily)
        context.insert(copy)
        context.insert(ActivityEvent(action: "Task created", taskTitle: copy.title, detail: "Re-added from review."))
        if copy.repeatsDaily {
            HabitTracker.ensureRoutine(for: copy, in: context)
        }
        readdedTitle = copy.title
    }
}
