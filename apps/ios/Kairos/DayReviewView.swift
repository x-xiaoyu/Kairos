import SwiftUI

struct DayReviewView: View {
    let events: [ActivityEvent]
    let completed: [KairosTask]
    @State private var showingCompleted = false

    private var today: [ActivityEvent] { events.filter { Calendar.current.isDateInToday($0.timestamp) } }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { Text("YOUR MOMENTUM").font(.caption2.bold()).tracking(1.5).foregroundStyle(Color.kairosPurple); Text("Review your day").font(.system(size: 36, weight: .bold, design: .serif)); Text("What you did, in the order it happened.").foregroundStyle(.secondary) }
                    HStack { completedStat; stat("\(completed.reduce(0) { $0 + $1.estimatedMinutes })m", "focused"); stat("\(today.filter { $0.action.contains("Focus") }.count)", "focus events") }
                    if showingCompleted { completedList } else { timeline(today, emptyTitle: "No activity yet") }
                }.padding(20)
            }
            .background(KairosTheme.background)
            .navigationTitle("回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }

    private func stat(_ value: String, _ label: String) -> some View { VStack(alignment: .leading) { Text(value).font(.title2.bold()).foregroundStyle(Color.kairosPurple); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(LinearGradient(colors: [.white, .kairosPurple.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6)) }

    private var completedStat: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { showingCompleted.toggle() } } label: {
            VStack(alignment: .leading) {
                HStack { Text("\(completed.count)").font(.title2.bold()); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
                Text("completed").font(.caption)
            }.foregroundStyle(Color.kairosPurple).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(LinearGradient(colors: [.white, .kairosPurple.opacity(showingCompleted ? 0.24 : 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.kairosPurple.opacity(showingCompleted ? 0.75 : 0.18), lineWidth: showingCompleted ? 2 : 1))
        }.buttonStyle(.plain).accessibilityHint("Shows all completed tasks")
    }

    private func timeline(_ items: [ActivityEvent], emptyTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty { ContentUnavailableView(emptyTitle, systemImage: "clock", description: Text("Your actions will appear here with their exact time.")) }
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
            HStack { Text("Completed tasks").font(.headline); Spacer(); Button("All activity") { withAnimation { showingCompleted = false } }.font(.caption.bold()) }
            if completed.isEmpty { ContentUnavailableView("No completed tasks", systemImage: "checkmark.circle", description: Text("Tasks appear here after you complete them.")) }
            ForEach(completed.sorted { completionDate(for: $0) > completionDate(for: $1) }) { task in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kairosGreen); Text(task.title).font(.headline); Spacer(); Text(completionDate(for: task).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                    if !task.goal.isEmpty { Text(task.goal).font(.subheadline).foregroundStyle(.secondary) }
                    HStack { Label("\(task.estimatedMinutes)m", systemImage: "timer"); Text("Priority \(task.priority)"); Spacer(); Button("Restore") { task.status = .todo }.font(.caption.bold()) }.font(.caption).foregroundStyle(.secondary)
                }.padding(14).background(Color.kairosGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 8)).transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func completionDate(for task: KairosTask) -> Date {
        events.first(where: { $0.action == "Completed" && $0.taskTitle == task.title })?.timestamp ?? task.createdAt
    }
}
