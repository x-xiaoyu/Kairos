import ActivityKit
import Foundation

struct KairosFocusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentMicroStep: String
        var isPaused: Bool
        var taskTitle: String
        var endDate: Date
    }

    var taskId: String
    var totalMinutes: Int
}
