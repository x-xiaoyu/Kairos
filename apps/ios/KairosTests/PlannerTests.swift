import XCTest
@testable import Kairos

@MainActor
final class PlannerTests: XCTestCase {
    func testFocusCountdownConsumesElapsedWallClockTime() {
        let task = KairosTask(title: "Concurrent task", estimatedMinutes: 5)
        var countdown = FocusCountdown(task: task)

        countdown.consume(90)
        XCTAssertEqual(countdown.secondsRemaining, 210)
        XCTAssertEqual(countdown.focusedSeconds, 90)

        countdown.consume(999)
        XCTAssertEqual(countdown.secondsRemaining, 0)
        XCTAssertEqual(countdown.focusedSeconds, 300)
    }

    func testLatestSafeStartIncludesHigherPriorityWork() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let deadline = now.addingTimeInterval(4 * 60 * 60)
        let urgent = KairosTask(title: "Urgent", deadline: deadline.addingTimeInterval(-3600), estimatedMinutes: 60, priority: 5, deadlineType: .hard)
        let target = KairosTask(title: "Target", deadline: deadline, estimatedMinutes: 30, priority: 3, deadlineType: .hard)
        let result = Planner.latestSafeStart(for: target, among: [urgent, target])
        XCTAssertEqual(result, deadline.addingTimeInterval(-105 * 60))
    }

    func testRiskBecomesCriticalAfterSafeStart() {
        let now = Date()
        XCTAssertEqual(Planner.risk(now: now, latestStart: now.addingTimeInterval(-1), estimatedMinutes: 30), .critical)
    }

    func testCompletedTasksAreExcluded() {
        let done = KairosTask(title: "Done", estimatedMinutes: 20, priority: 5, status: .complete)
        let next = KairosTask(title: "Next", estimatedMinutes: 30, priority: 3)
        XCTAssertEqual(Planner.makePlan(tasks: [done, next]).map(\.task.id), [next.id])
    }

    func testPlanOrdersWithinDayByPriorityThenDeadlineAndKeepsNewestLast() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sharedDeadline = now.addingTimeInterval(7_200)
        let older = KairosTask(title: "Older", deadline: sharedDeadline, priority: 3)
        older.createdAt = now
        let newer = KairosTask(title: "Newer", deadline: sharedDeadline, priority: 3)
        newer.createdAt = now.addingTimeInterval(1)
        let earlier = KairosTask(title: "Earlier deadline", deadline: now.addingTimeInterval(3_600), priority: 1)
        earlier.createdAt = now.addingTimeInterval(2)

        XCTAssertEqual(Planner.makePlan(tasks: [newer, earlier, older], now: now).map(\.task.title), ["Older", "Newer", "Earlier deadline"])
    }

    func testPostponeOnlyMovesTaskWithinItsOwnDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9))!
        let todayDeadline = calendar.date(byAdding: .hour, value: 3, to: now)!
        let tomorrowDeadline = calendar.date(byAdding: .day, value: 1, to: todayDeadline)!
        let first = KairosTask(title: "First today", deadline: todayDeadline, priority: 5)
        let second = KairosTask(title: "Second today", deadline: todayDeadline.addingTimeInterval(600), priority: 1)
        let tomorrow = KairosTask(title: "Tomorrow", deadline: tomorrowDeadline, priority: 5)

        Planner.postponeWithinDay(first, among: [first, second, tomorrow], minutes: 30, now: now, calendar: calendar)
        let plan = Planner.makePlan(tasks: [first, second, tomorrow], now: now)

        XCTAssertEqual(plan.map(\.task.title), ["Second today", "First today", "Tomorrow"])
        XCTAssertEqual(plan.last?.start, calendar.startOfDay(for: tomorrowDeadline))
    }

    func testPostponeSwapsOnlyWithTheAdjacentTask() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9))!
        let deadline = calendar.date(byAdding: .hour, value: 3, to: now)!
        let first = KairosTask(title: "First", deadline: deadline, priority: 5)
        let second = KairosTask(title: "Second", deadline: deadline.addingTimeInterval(600), priority: 3)
        let third = KairosTask(title: "Third", deadline: deadline.addingTimeInterval(1_200), priority: 1)

        Planner.postponeWithinDay(first, among: [first, second, third], minutes: 30, now: now, calendar: calendar)

        XCTAssertEqual(Planner.makePlan(tasks: [first, second, third], now: now).map(\.task.title), ["Second", "First", "Third"])
    }

    func testExplicitStartTimeControlsPlannedStart() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let scheduledStart = now.addingTimeInterval(3_600)
        let task = KairosTask(title: "Scheduled", deadline: now.addingTimeInterval(7_200), scheduledStart: scheduledStart)

        XCTAssertEqual(Planner.makePlan(tasks: [task], now: now).first?.start, scheduledStart)
    }
}
