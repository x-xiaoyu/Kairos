import ActivityKit
import Foundation

@MainActor
enum LiveActivityManager {
    private static var pipeline: Task<Void, Never>?

    static func start(task: KairosTask, secondsRemaining: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(for: task, secondsRemaining: secondsRemaining, isPaused: false)
        let attributes = KairosFocusAttributes(taskId: task.id.uuidString, totalMinutes: max(1, task.estimatedMinutes))
        enqueue {
            await endExisting()
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: state.endDate.addingTimeInterval(120)),
                    pushType: nil
                )
            } catch {
            }
        }
    }

    static func update(task: KairosTask, secondsRemaining: Int, isPaused: Bool) {
        let state = contentState(for: task, secondsRemaining: secondsRemaining, isPaused: isPaused)
        enqueue {
            for activity in Activity<KairosFocusAttributes>.activities {
                await activity.update(.init(state: state, staleDate: isPaused ? nil : state.endDate.addingTimeInterval(120)))
            }
        }
    }

    static func end() {
        enqueue { await endExisting() }
    }

    private static func enqueue(_ work: @escaping () async -> Void) {
        pipeline = Task { [pipeline] in
            _ = await pipeline?.value
            await work()
        }
    }

    static func contentState(for task: KairosTask, secondsRemaining: Int, isPaused: Bool, now: Date = .now) -> KairosFocusAttributes.ContentState {
        let remaining = TimeInterval(max(0, secondsRemaining))
        return KairosFocusAttributes.ContentState(
            currentMicroStep: microStep(for: task),
            isPaused: isPaused,
            taskTitle: task.title,
            endDate: isPaused ? Date(timeIntervalSinceReferenceDate: remaining) : now.addingTimeInterval(remaining)
        )
    }

    static func microStep(for task: KairosTask) -> String {
        KairosAdvisor.generateLocalNudge(for: task, stage: .start).microStep
    }

    static func remaining(from state: KairosFocusAttributes.ContentState, now: Date = .now, lastUpdated _: Date? = nil) -> TimeInterval {
        if state.isPaused {
            return max(0, state.endDate.timeIntervalSinceReferenceDate)
        }
        return max(0, state.endDate.timeIntervalSince(now))
    }

    private static func endExisting() async {
        for activity in Activity<KairosFocusAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
