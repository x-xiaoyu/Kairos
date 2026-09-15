import ActivityKit
import SwiftUI
import WidgetKit

struct KairosLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KairosFocusAttributes.self) { context in
            lockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.taskTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context: context, compact: false, large: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("💡 眼前只做：\(context.state.currentMicroStep)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } compactLeading: {
                Circle()
                    .fill(Color(red: 0.52, green: 0.38, blue: 0.82))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
            } compactTrailing: {
                countdown(context: context, compact: true)
            } minimal: {
                Circle()
                    .fill(Color(red: 0.52, green: 0.38, blue: 0.82))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func lockScreen(context: ActivityViewContext<KairosFocusAttributes>) -> some View {
        let remaining = remainingSeconds(context: context)
        let total = max(1, context.attributes.totalMinutes * 60)
        let progress = min(1, max(0, 1 - remaining / Double(total)))

        return VStack(alignment: .leading, spacing: 12) {
            Text(context.state.isPaused ? "专注已暂停" : "专注进行中")
                .font(.caption.bold())
                .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.25))
            Text(context.state.taskTitle)
                .font(.headline)
                .lineLimit(1)
            Text("💡 眼前只做：\(context.state.currentMicroStep)")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ProgressView(value: progress)
                    .tint(Color(red: 0.52, green: 0.38, blue: 0.82))
                countdown(context: context, compact: false)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .activityBackgroundTint(Color(red: 0.18, green: 0.16, blue: 0.38))
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    private func countdown(context: ActivityViewContext<KairosFocusAttributes>, compact: Bool, large: Bool = false) -> some View {
        let font: Font = {
            if compact { return .caption.monospacedDigit().weight(.semibold) }
            if large { return .title.monospacedDigit().weight(.semibold) }
            return .title3.monospacedDigit().weight(.semibold)
        }()
        if context.state.isPaused {
            Text(pausedClock(context: context))
                .font(font)
                .foregroundStyle(.secondary)
        } else if context.state.endDate > .now {
            Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: compact ? 52 : (large ? 92 : 76), alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text("00:00")
                .font(font)
        }
    }

    private func remainingSeconds(context: ActivityViewContext<KairosFocusAttributes>) -> Double {
        if context.state.isPaused {
            return max(0, context.state.endDate.timeIntervalSinceReferenceDate)
        }
        return max(0, context.state.endDate.timeIntervalSinceNow)
    }

    private func pausedClock(context: ActivityViewContext<KairosFocusAttributes>) -> String {
        let remaining = Int(remainingSeconds(context: context).rounded(.down))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}
