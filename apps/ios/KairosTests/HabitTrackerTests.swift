import XCTest
@testable import Kairos

final class HabitTrackerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10, minute: 0))!
    }

    func testNextOccurrenceStaysTodayWhenTimeHasNotPassed() {
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 6, minute: 30))!
        let next = HabitTracker.nextOccurrence(hour: 7, minute: 0, after: morning, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: next), 15)
        XCTAssertEqual(calendar.component(.hour, from: next), 7)
        XCTAssertEqual(calendar.component(.minute, from: next), 0)
    }

    func testNextOccurrenceMovesToTomorrowWhenTimeHasPassed() {
        let next = HabitTracker.nextOccurrence(hour: 7, minute: 0, after: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: next), 16)
        XCTAssertEqual(calendar.component(.hour, from: next), 7)
    }

    func testMissedDayResetsStreakToZero() {
        let last = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 7))!
        XCTAssertEqual(HabitTracker.streakAfterMissedDays(currentStreak: 8, lastCompletedDay: last, now: now, calendar: calendar), 0)
    }

    func testYesterdayDoesNotResetStreak() {
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 7))!
        XCTAssertEqual(HabitTracker.streakAfterMissedDays(currentStreak: 8, lastCompletedDay: yesterday, now: now, calendar: calendar), 8)
        XCTAssertEqual(HabitTracker.streakAfterCheckIn(currentStreak: 8, lastCompletedDay: yesterday, now: now, calendar: calendar), 9)
    }

    func testSameDayCheckInDoesNotDoubleCount() {
        XCTAssertEqual(HabitTracker.streakAfterCheckIn(currentStreak: 3, lastCompletedDay: now, now: now, calendar: calendar), 3)
    }

    func testFirstCheckInStartsAtOne() {
        XCTAssertEqual(HabitTracker.streakAfterCheckIn(currentStreak: 0, lastCompletedDay: nil, now: now, calendar: calendar), 1)
    }

    func testBestStreakKeepsTheHighWaterMark() {
        XCTAssertEqual(HabitTracker.bestStreak(currentBest: 12, newStreak: 4), 12)
        XCTAssertEqual(HabitTracker.bestStreak(currentBest: 12, newStreak: 13), 13)
    }

    func testDuplicatingTaskKeepsRepeatMetadata() {
        let task = KairosTask(title: "健身", estimatedMinutes: 45, repeatsDaily: true, repeatHour: 7, repeatMinute: 30)
        let copy = task.duplicatedAsTodo(scheduledStart: now, keepRepeat: true)
        XCTAssertNotEqual(copy.id, task.id)
        XCTAssertEqual(copy.title, "健身")
        XCTAssertEqual(copy.status, .todo)
        XCTAssertTrue(copy.repeatsDaily)
        XCTAssertEqual(copy.repeatHour, 7)
        XCTAssertEqual(copy.repeatMinute, 30)
        XCTAssertEqual(copy.scheduledStart, now)
    }
}
