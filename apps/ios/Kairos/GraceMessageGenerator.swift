import SwiftUI
import UIKit

struct GraceMessage: Equatable, Identifiable {
    let scenarioTitle: String
    let messageBody: String
    var id: String { scenarioTitle }
}

enum GraceMessageTrigger: Equatable {
    case postponed
    case missedStart
    case highRisk
    case overdue

    var eyebrow: String {
        switch self {
        case .postponed: "顺延不扣分。如果需要对外说一声，这里有现成的措辞。"
        case .missedStart: "计划开始时间已经过了，也可以只先发一句说明，不必解释整段故事。"
        case .highRisk: "时间有点紧。一句清楚的更新，往往比沉默更轻松。"
        case .overdue: "超期很常见。先给对方一个具体时间点，比道歉长文更有用。"
        }
    }
}

enum GraceMessageAudience: String, CaseIterable, Equatable {
    case colleague
    case advisor
    case friend

    var title: String {
        switch self {
        case .colleague: "向同事/团队说明"
        case .advisor: "向教授/导师说明"
        case .friend: "给朋友解释"
        }
    }
}

struct GraceMessageOffer: Identifiable {
    let task: KairosTask
    let trigger: GraceMessageTrigger
    var revisedStart: Date?
    var id: UUID { task.id }
}

enum GraceMessageGenerator {
    static func messages(for task: KairosTask, trigger: GraceMessageTrigger, now: Date = .now, revisedStart: Date? = nil) -> [GraceMessage] {
        preferredAudiences(for: task).map { audience in
            GraceMessage(
                scenarioTitle: audience.title,
                messageBody: body(for: task, audience: audience, trigger: trigger, now: now, revisedStart: revisedStart)
            )
        }
    }

    static func preferredAudiences(for task: KairosTask) -> [GraceMessageAudience] {
        let text = (task.title + " " + task.goal).lowercased()
        if ["作业", "论文", "课", "教授", "导师", "答辩", "homework", "thesis", "professor"].contains(where: text.contains) {
            return [.advisor, .colleague, .friend]
        }
        if ["朋友", "聚会", "晚饭", "约"].contains(where: text.contains) {
            return [.friend, .colleague, .advisor]
        }
        return [.colleague, .advisor, .friend]
    }

    private static func body(for task: KairosTask, audience: GraceMessageAudience, trigger: GraceMessageTrigger, now: Date, revisedStart: Date?) -> String {
        let when = timePhrase(for: task, now: now, revisedStart: revisedStart)
        switch (audience, trigger) {
        case (.colleague, .postponed):
            return "Hi，同步一下「\(task.title)」。我需要把顺序微调一下，预计在\(when)给你更新。如果有必须先对齐的部分，直接说即可。"
        case (.colleague, .missedStart):
            return "Hi，原计划开始的「\(task.title)」我这边晚了一点。我正在往下做，预计\(when)同步进度。有卡点我再单独说。"
        case (.colleague, .highRisk):
            return "Hi，「\(task.title)」的时间比预想更紧。我会先交出最关键的一截，完整更新预计在\(when)。有需要提前看的材料告诉我。"
        case (.colleague, .overdue):
            return "Hi，「\(task.title)」比原计划晚了。我正在收尾，会在\(when)给你一个明确更新，避免你空等。"
        case (.advisor, .postponed):
            return "老师/导师您好，关于「\(task.title)」，我需要把处理顺序往后挪一点。当前计划在\(when)完成并同步给您。感谢理解。"
        case (.advisor, .missedStart):
            return "老师/导师您好，「\(task.title)」我比原定开始时间晚了一些。我会继续推进，并在\(when)把进展发给您。"
        case (.advisor, .highRisk):
            return "老师/导师您好，「\(task.title)」目前时间比较紧。我会先完成最核心的部分，并在\(when)向您汇报。"
        case (.advisor, .overdue):
            return "老师/导师您好，「\(task.title)」比原定时间晚了。我正在收尾，会在\(when)把可讨论的版本发给您。"
        case (.friend, .postponed):
            return "我这边「\(task.title)」要晚一点才能弄完，大概\(when)好。不是消失了，做完就找你。"
        case (.friend, .missedStart):
            return "「\(task.title)」我刚才没能准时开始，正在补上，大概\(when)能告一段落。到时候再联系你。"
        case (.friend, .highRisk):
            return "今天「\(task.title)」有点赶。我先把它推过关键一步，大概\(when)能喘口气，到时再约。"
        case (.friend, .overdue):
            return "「\(task.title)」我晚了，正在收尾，预计\(when)能给你准信。先不用等我。"
        }
    }

    private static func timePhrase(for task: KairosTask, now: Date, revisedStart: Date?) -> String {
        if let revisedStart, revisedStart > now {
            return revisedStart.formatted(date: .omitted, time: .shortened)
        }
        if let deadline = task.deadline, deadline > now {
            return "\(deadline.formatted(date: .omitted, time: .shortened)) 前"
        }
        let fallback = now.addingTimeInterval(TimeInterval(max(30, task.estimatedMinutes) * 60))
        return fallback.formatted(date: .omitted, time: .shortened) + " 左右"
    }
}

struct GraceMessageSheet: View {
    let task: KairosTask
    let trigger: GraceMessageTrigger
    var revisedStart: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var copiedTitle: String?

    private var messages: [GraceMessage] {
        GraceMessageGenerator.messages(for: task, trigger: trigger, revisedStart: revisedStart)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("体面说明").font(.caption.bold()).foregroundStyle(Color.kairosIndigo)
                        Text("不必解释自己。选一条复制或分享即可。").font(.title2.bold())
                        Text(trigger.eyebrow).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(message.scenarioTitle).font(.headline)
                            Text(message.messageBody).font(.body).foregroundStyle(.primary)
                            HStack(spacing: 10) {
                                Button {
                                    UIPasteboard.general.string = message.messageBody
                                    copiedTitle = message.scenarioTitle
                                } label: {
                                    Label(copiedTitle == message.scenarioTitle ? "已复制" : "复制", systemImage: copiedTitle == message.scenarioTitle ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.borderedProminent)
                                ShareLink(item: message.messageBody) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kairosPurple.opacity(0.16)))
                    }
                }
                .padding(20)
            }
            .background(KairosTheme.background)
            .navigationTitle("“\(task.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("这次不用") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
