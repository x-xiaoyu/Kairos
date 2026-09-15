import XCTest
@testable import Kairos

@MainActor
final class TimeBiasReflectorTests: XCTestCase {
    func testInsufficientSamplesStayNeutral() {
        let task = completedTask("Draft", estimated: 30, load: .high)
        let events = [completedEvent("Draft", actual: 50, estimated: 30, load: .high)]
        let profile = TimeBiasReflector.profile(tasks: [task], events: events)
        XCTAssertEqual(profile.overallRatio, 1)
        XCTAssertTrue(profile.insights.isEmpty)
    }

    func testHighLoadUnderestimateProducesBufferInsight() {
        let tasks = [
            completedTask("论文 1", estimated: 30, load: .high),
            completedTask("论文 2", estimated: 30, load: .high)
        ]
        let events = [
            completedEvent("论文 1", actual: 45, estimated: 30, load: .high),
            completedEvent("论文 2", actual: 45, estimated: 30, load: .high)
        ]
        let profile = TimeBiasReflector.profile(tasks: tasks, events: events)
        XCTAssertEqual(profile.sampleCount, 2)
        XCTAssertEqual(profile.overallRatio, 1.5, accuracy: 0.01)
        XCTAssertEqual(profile.adjustment(for: .high), 1.5, accuracy: 0.01)
        let insight = TimeBiasReflector.insight(for: .high, tasks: tasks, events: events)
        XCTAssertEqual(insight?.averageUnderestimateMinutes, 15)
        XCTAssertEqual(insight?.typicalMinutes, 45)
        XCTAssertEqual(
            insight?.recommendationText,
            "💡 Kairos 洞察：基于过去 2 次专注记录，这类任务预留 45 分钟会更从容。"
        )
        XCTAssertEqual(insight?.message(forEstimatedMinutes: 30), insight?.recommendationText)
    }

    func testCalibratedDurationAppliesOnlyAboveUnderestimateThreshold() {
        let task = KairosTask(title: "报告", estimatedMinutes: 30, cognitiveLoad: .high)
        let strong = TimeBiasProfile(overallRatio: 1.5, ratioByLoad: [.high: 1.5], insights: [], sampleCount: 3)
        let mild = TimeBiasProfile(overallRatio: 1.15, ratioByLoad: [.high: 1.15], insights: [], sampleCount: 3)
        XCTAssertEqual(TimeBiasReflector.calibratedDuration(for: task, bias: strong), 45)
        XCTAssertEqual(TimeBiasReflector.calibratedDuration(for: task, bias: mild), 30)
    }

    func testDeclinedCalibrationKeepsEstimateAndRaisesRisk() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let deadline = now.addingTimeInterval(90 * 60)
        let task = KairosTask(title: "论文", deadline: deadline, estimatedMinutes: 30, cognitiveLoad: .high, deadlineType: .hard)
        let bias = TimeBiasProfile(overallRatio: 1.5, ratioByLoad: [.high: 1.5], insights: [], sampleCount: 3)

        let automatic = Planner.makePlan(tasks: [task], now: now, bias: bias).first
        XCTAssertEqual(automatic.map { $0.end.timeIntervalSince($0.start) }, 45 * 60)
        XCTAssertEqual(automatic?.risk, .high)

        task.timeBiasCalibration = .declined
        let declined = Planner.makePlan(tasks: [task], now: now, bias: bias).first
        XCTAssertEqual(declined.map { $0.end.timeIntervalSince($0.start) }, 30 * 60)
        XCTAssertEqual(declined?.latestSafeStart, deadline.addingTimeInterval(-45 * 60))
        XCTAssertEqual(declined?.risk, .high)

        task.timeBiasCalibration = .automatic
        let unbiased = Planner.makePlan(tasks: [task], now: now).first
        XCTAssertEqual(unbiased?.risk, .warning)
    }

    func testAcceptedCalibrationDoesNotDoubleApply() {
        let task = KairosTask(title: "设计评审", estimatedMinutes: 45, cognitiveLoad: .high)
        task.timeBiasCalibration = .accepted
        let bias = TimeBiasProfile(overallRatio: 1.5, ratioByLoad: [.high: 1.5], insights: [], sampleCount: 3)
        XCTAssertEqual(TimeBiasReflector.calibratedDuration(for: task, bias: bias), 45)
        XCTAssertEqual(TimeBiasReflector.calibratedDuration(for: task, bias: bias, ignoreDecline: true), 68)
    }

    func testAgentInsightCopyUsesSampleCountAndReservedMinutes() {
        XCTAssertEqual(
            TimeBiasReflector.agentInsightText(sampleCount: 3, reservedMinutes: 45),
            "💡 Kairos 洞察：基于过去 3 次专注记录，这类任务预留 45 分钟会更从容。"
        )
        XCTAssertEqual(TimeBiasReflector.reservedMinutes(estimated: 30, biasRatio: 1.5), 45)
        XCTAssertEqual(TimeBiasReflector.reservedMinutes(estimated: 30, biasRatio: 1.1), 30)
    }

    func testLoadSpecificBiasDoesNotBleedIntoOtherLoads() {
        let tasks = [
            completedTask("高 1", estimated: 20, load: .high),
            completedTask("高 2", estimated: 20, load: .high),
            completedTask("低 1", estimated: 20, load: .low),
            completedTask("低 2", estimated: 20, load: .low)
        ]
        let events = [
            completedEvent("高 1", actual: 40, estimated: 20, load: .high),
            completedEvent("高 2", actual: 40, estimated: 20, load: .high),
            completedEvent("低 1", actual: 20, estimated: 20, load: .low),
            completedEvent("低 2", actual: 20, estimated: 20, load: .low)
        ]
        let profile = TimeBiasReflector.profile(tasks: tasks, events: events)
        XCTAssertEqual(profile.adjustment(for: .high), 1.8, accuracy: 0.01)
        XCTAssertEqual(profile.adjustment(for: .low), 1, accuracy: 0.01)
    }

    func testPlannerAppliesBiasToLatestSafeStartAndDuration() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let deadline = now.addingTimeInterval(4 * 60 * 60)
        let task = KairosTask(title: "Target", deadline: deadline, estimatedMinutes: 30, cognitiveLoad: .high, deadlineType: .hard)
        let bias = TimeBiasProfile(overallRatio: 1.5, ratioByLoad: [.high: 1.5], insights: [], sampleCount: 4)

        let latest = Planner.latestSafeStart(for: task, among: [task], bias: bias)
        XCTAssertEqual(latest, deadline.addingTimeInterval(-60 * 60))

        let plan = Planner.makePlan(tasks: [task], now: now, bias: bias)
        XCTAssertEqual(plan.first.map { $0.end.timeIntervalSince($0.start) }, 45 * 60)
    }

    func testIgnoresCompletionsWithoutActualDuration() {
        let task = completedTask("Inbox", estimated: 20, load: .medium)
        let events = [
            ActivityEvent(action: "Completed", taskTitle: "Inbox", detail: "Task marked complete."),
            ActivityEvent(action: "Completed", taskTitle: "Inbox", detail: "Task marked complete.")
        ]
        XCTAssertEqual(TimeBiasReflector.profile(tasks: [task], events: events), .neutral)
    }

    private func completedTask(_ title: String, estimated: Int, load: CognitiveLoad) -> KairosTask {
        KairosTask(title: title, estimatedMinutes: estimated, status: .complete, cognitiveLoad: load)
    }

    private func completedEvent(_ title: String, actual: Int, estimated: Int, load: CognitiveLoad) -> ActivityEvent {
        ActivityEvent(
            action: "Completed",
            taskTitle: title,
            detail: "Finished from focus mode after \(actual) minute(s). Estimated \(estimated) minutes. Load \(load.rawValue)."
        )
    }
}
