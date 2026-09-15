import CoreLocation
import XCTest
@testable import Kairos

@MainActor
final class PlaceContextTests: XCTestCase {
    private let home = CLLocation(latitude: 40.7128, longitude: -74.0060)
    private let homePlace = HomeLocation(latitude: 40.7128, longitude: -74.0060, address: "家")

    func testNearbyCoordinateCountsAsHome() {
        let nearby = CLLocation(latitude: 40.7135, longitude: -74.0060)
        XCTAssertEqual(PlaceContext.presence(current: nearby, home: homePlace), .atHome)
    }

    func testDistantCoordinateCountsAsAway() {
        let away = CLLocation(latitude: 40.7580, longitude: -73.9855)
        XCTAssertEqual(PlaceContext.presence(current: away, home: homePlace), .away)
    }

    func testMissingHomeOrLocationIsUnknown() {
        XCTAssertEqual(PlaceContext.presence(current: home, home: nil), .unknown)
        XCTAssertEqual(PlaceContext.presence(current: nil, home: homePlace), .unknown)
    }

    func testManualHomeOverrideIgnoresLocation() {
        let away = CLLocation(latitude: 40.7580, longitude: -73.9855)
        XCTAssertEqual(PlaceContext.resolvedPresence(mode: .home, current: away, home: homePlace), .atHome)
        XCTAssertEqual(PlaceContext.resolvedPresence(mode: .away, current: home, home: homePlace), .away)
        XCTAssertEqual(PlaceContext.resolvedPresence(mode: .auto, current: away, home: homePlace), .away)
    }

    func testLaundryIsDoableAtHomeAndShoppingIsNot() {
        XCTAssertTrue(PlaceContext.isDoableNow(.home, presence: .atHome))
        XCTAssertTrue(PlaceContext.isDoableNow(.anywhere, presence: .atHome))
        XCTAssertFalse(PlaceContext.isDoableNow(.outing, presence: .atHome))
        XCTAssertTrue(PlaceContext.isDoableNow(.outing, presence: .away))
        XCTAssertFalse(PlaceContext.isDoableNow(.home, presence: .away))
    }

    func testUrgentOutingStaysVisibleAtHome() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let laundry = KairosTask(title: "洗衣服", estimatedMinutes: 20, cognitiveLoad: .low, place: .home)
        let shopping = KairosTask(title: "采购", deadline: now.addingTimeInterval(-60), estimatedMinutes: 30, priority: 5, cognitiveLoad: .low, deadlineType: .hard, place: .outing)
        let plan = Planner.makePlan(tasks: [laundry, shopping], now: now)
        XCTAssertEqual(PlaceContext.suggestedStart(in: plan, presence: .atHome)?.task.title, "采购")
        XCTAssertTrue(plan.contains { PlaceContext.shouldHighlightNow($0, presence: .atHome) && $0.task.title == "采购" })
    }

    func testAtHomePrefersCognitiveWorkOverChores() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let laundry = KairosTask(title: "洗衣服", estimatedMinutes: 20, priority: 5, cognitiveLoad: .low, place: .home)
        laundry.createdAt = now
        let report = KairosTask(title: "写报告", estimatedMinutes: 40, priority: 3, cognitiveLoad: .high, place: .home)
        report.createdAt = now.addingTimeInterval(1)
        let shopping = KairosTask(title: "采购", estimatedMinutes: 30, priority: 4, cognitiveLoad: .low, place: .outing)
        shopping.createdAt = now.addingTimeInterval(2)
        let plan = Planner.makePlan(tasks: [laundry, report, shopping], now: now)
        XCTAssertEqual(PlaceContext.suggestedStart(in: plan, presence: .atHome)?.task.title, "写报告")
        XCTAssertFalse(plan.first { $0.task.title == "采购" }.map { PlaceContext.shouldHighlightNow($0, presence: .atHome) } ?? true)
    }

    func testTitleGuessesPlaceAndLoad() {
        XCTAssertEqual(TaskContextGuess.place(from: "洗衣服"), .home)
        XCTAssertEqual(TaskContextGuess.place(from: "去超市采购"), .outing)
        XCTAssertEqual(TaskContextGuess.place(from: "写周报"), .anywhere)
        XCTAssertEqual(TaskContextGuess.cognitiveLoad(from: "写报告"), .high)
        XCTAssertEqual(TaskContextGuess.cognitiveLoad(from: "洗碗"), .low)
    }
}
