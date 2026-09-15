import Foundation
import WidgetKit

enum WidgetSnapshotStore {
    static let suiteName = "group.com.xiaoyu.kairos"
    private static let storageKey = "kairos.widget.snapshot"

    struct Snapshot: Codable, Equatable {
        let countdownTitle: String?
        let countdownDeadline: Date?
        let nextTaskTitle: String?
        let nextTaskStart: Date?
    }

    static func update(plan: [PlannedTask], primaryCountdown: KairosTask?) {
        let next = plan.first
        let snapshot = Snapshot(
            countdownTitle: primaryCountdown?.title,
            countdownDeadline: primaryCountdown?.deadline,
            nextTaskTitle: next?.task.title,
            nextTaskStart: next?.start
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "KairosCountdownWidget")
    }
}
