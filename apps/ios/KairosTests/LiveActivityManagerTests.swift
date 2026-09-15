import XCTest
@testable import Kairos

@MainActor
final class LiveActivityManagerTests: XCTestCase {
    func testContentStateUsesMicroStepAndEndDate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let task = KairosTask(title: "写周报", estimatedMinutes: 30, cognitiveLoad: .medium)
        let state = LiveActivityManager.contentState(for: task, secondsRemaining: 125, isPaused: false, now: now)
        XCTAssertEqual(state.taskTitle, "写周报")
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(state.endDate, now.addingTimeInterval(125))
        XCTAssertFalse(state.currentMicroStep.isEmpty)
        XCTAssertFalse(NudgeEngine.isJudgmental(state.currentMicroStep))
    }

    func testPausedRemainingStaysAnchoredToUpdateTime() {
        let updatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let task = KairosTask(title: "接口联调", estimatedMinutes: 20)
        let state = LiveActivityManager.contentState(for: task, secondsRemaining: 90, isPaused: true, now: updatedAt)
        let later = updatedAt.addingTimeInterval(40)
        XCTAssertEqual(LiveActivityManager.remaining(from: state, now: later, lastUpdated: updatedAt), 90)
        XCTAssertEqual(LiveActivityManager.remaining(from: state, now: later), 90)
    }
}
