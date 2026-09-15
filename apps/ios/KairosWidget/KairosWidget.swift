import SwiftUI
import WidgetKit

private let suiteName = "group.com.xiaoyu.kairos"
private let storageKey = "kairos.widget.snapshot"

private struct KairosWidgetSnapshot: Codable {
    let countdownTitle: String?
    let countdownDeadline: Date?
    let nextTaskTitle: String?
    let nextTaskStart: Date?
}

private struct KairosWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: KairosWidgetSnapshot?
}

private struct KairosWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KairosWidgetEntry {
        KairosWidgetEntry(date: .now, snapshot: .init(countdownTitle: "LeetCode 150", countdownDeadline: Calendar.current.date(byAdding: .day, value: 12, to: .now), nextTaskTitle: "完成今天的 8 道题", nextTaskStart: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (KairosWidgetEntry) -> Void) {
        completion(KairosWidgetEntry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KairosWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = KairosWidgetEntry(date: now, snapshot: loadSnapshot())
        let nextMidnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func loadSnapshot() -> KairosWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(KairosWidgetSnapshot.self, from: data)
    }
}

private struct KairosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KairosWidgetEntry

    private var remainingDays: Int? {
        guard let deadline = entry.snapshot?.countdownDeadline else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: calendar.startOfDay(for: deadline)).day ?? 0
        return max(0, days)
    }

    private var deadlineText: String? {
        entry.snapshot?.countdownDeadline?.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits).weekday(.wide)
        )
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                if let days = remainingDays {
                    VStack(spacing: 8) {
                        Text("距离\(entry.snapshot?.countdownTitle ?? "目标")还有")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("\(days)")
                                .font(.system(size: 68, weight: .regular))
                                .monospacedDigit()
                            Text("天")
                                .font(.title3)
                        }
                        .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        Text(deadlineText ?? "")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("请先设置主要倒数日")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.indigo)
                        .frame(width: 5)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("接下来")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(entry.snapshot?.nextTaskTitle ?? "暂无待办任务")
                            .font(.title2.bold())
                            .lineLimit(2)
                        if let start = entry.snapshot?.nextTaskStart {
                            Text(start, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.white, Color.indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

@main
struct KairosCountdownWidget: Widget {
    let kind = "KairosCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KairosWidgetProvider()) { entry in
            KairosWidgetView(entry: entry)
        }
        .configurationDisplayName("Kairos 倒数日")
        .description("显示主要倒数日和接下来要做的任务。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
