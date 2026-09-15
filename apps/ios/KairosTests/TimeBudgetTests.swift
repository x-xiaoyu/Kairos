import XCTest
@testable import Kairos

@MainActor
final class TimeBudgetTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testFourThirtyMinuteTasksWithOneHourLeftPicksHighestPriority() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 0))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 0))!
        let laundry = task("洗衣服", minutes: 30, priority: 2, load: .low, deadline: deadline, createdAt: now)
        let shopping = task("采购", minutes: 30, priority: 3, load: .low, deadline: deadline, createdAt: now.addingTimeInterval(1))
        let interview = task("准备面试", minutes: 30, priority: 5, load: .high, deadline: deadline, createdAt: now.addingTimeInterval(2))
        let dishes = task("洗碗", minutes: 30, priority: 1, load: .low, deadline: deadline, createdAt: now.addingTimeInterval(3))
        let plan = Planner.makePlan(tasks: [laundry, shopping, interview, dishes], now: now)
        let budget = TimeBudget.evaluate(plan: plan, now: now, presence: .atHome, calendar: calendar)

        XCTAssertEqual(budget.remainingMinutes, 60)
        XCTAssertEqual(budget.neededMinutes, 120)
        XCTAssertEqual(budget.taskCount, 4)
        XCTAssertTrue(budget.isShort)
        XCTAssertEqual(budget.pick?.task.title, "准备面试")
    }

    func testHardDeadlineBeatsHigherSoftPriorityWhenTimeIsShort() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21, minute: 0))!
        let soon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 0))!
        let later = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 30))!
        let reading = task("泛读", minutes: 30, priority: 5, load: .medium, deadline: later, type: .soft, createdAt: now)
        let submit = task("提交申请", minutes: 30, priority: 3, load: .medium, deadline: soon, type: .hard, createdAt: now.addingTimeInterval(1))
        let extra = task("整理桌面", minutes: 30, priority: 1, load: .low, deadline: later, type: .soft, createdAt: now.addingTimeInterval(2))
        let plan = Planner.makePlan(tasks: [reading, submit, extra], now: now)
        let budget = TimeBudget.evaluate(plan: plan, now: now, calendar: calendar)

        XCTAssertTrue(budget.isShort)
        XCTAssertEqual(budget.pick?.task.title, "提交申请")
    }

    func testEnoughTimeKeepsPlaceAwareSuggestion() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10, minute: 0))!
        let laundry = task("洗衣服", minutes: 20, priority: 5, load: .low, place: .home, createdAt: now)
        let report = task("写报告", minutes: 40, priority: 3, load: .high, place: .home, createdAt: now.addingTimeInterval(1))
        let shopping = task("采购", minutes: 30, priority: 4, load: .low, place: .outing, createdAt: now.addingTimeInterval(2))
        let plan = Planner.makePlan(tasks: [laundry, report, shopping], now: now)
        let budget = TimeBudget.evaluate(plan: plan, now: now, presence: .atHome, calendar: calendar)

        XCTAssertFalse(budget.isShort)
        XCTAssertEqual(budget.pick?.task.title, "写报告")
    }

    func testSingleOversizedTaskIsNotTreatedAsCompetingOverflow() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 0))!
        let deepWork = task("写论文", minutes: 90, priority: 5, load: .high, createdAt: now)
        let plan = Planner.makePlan(tasks: [deepWork], now: now)
        let budget = TimeBudget.evaluate(plan: plan, now: now, calendar: calendar)

        XCTAssertEqual(budget.taskCount, 1)
        XCTAssertFalse(budget.isShort)
        XCTAssertEqual(budget.pick?.task.title, "写论文")
    }

    private func task(
        _ title: String,
        minutes: Int,
        priority: Int,
        load: CognitiveLoad,
        deadline: Date? = nil,
        type: DeadlineType = .soft,
        place: TaskPlace = .anywhere,
        createdAt: Date
    ) -> KairosTask {
        let item = KairosTask(
            title: title,
            deadline: deadline,
            estimatedMinutes: minutes,
            priority: priority,
            cognitiveLoad: load,
            deadlineType: deadline == nil ? .none : type,
            place: place
        )
        item.createdAt = createdAt
        return item
    }
}
