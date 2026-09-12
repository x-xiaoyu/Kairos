import XCTest
@testable import Kairos

@MainActor
final class PlannerTests: XCTestCase {
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

    func testPlanOrdersByDeadlineThenKeepsNewestLast() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sharedDeadline = now.addingTimeInterval(7_200)
        let older = KairosTask(title: "Older", deadline: sharedDeadline, priority: 3)
        older.createdAt = now
        let newer = KairosTask(title: "Newer", deadline: sharedDeadline, priority: 3)
        newer.createdAt = now.addingTimeInterval(1)
        let earlier = KairosTask(title: "Earlier deadline", deadline: now.addingTimeInterval(3_600), priority: 1)
        earlier.createdAt = now.addingTimeInterval(2)

        XCTAssertEqual(Planner.makePlan(tasks: [newer, earlier, older], now: now).map(\.task.title), ["Earlier deadline", "Older", "Newer"])
    }
}
