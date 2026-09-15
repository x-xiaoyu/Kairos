import XCTest
@testable import Kairos

@MainActor
final class FocusSessionStoreTests: XCTestCase {
    override func tearDown() {
        FocusSessionStore.clear()
        super.tearDown()
    }

    func testStandardFocusReplaysElapsedForUnpausedSessionsOnly() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let state = PersistedFocusState(
            sessions: [
                PersistedFocusSession(taskId: UUID(), startedAt: now, secondsRemaining: 300, focusedSeconds: 0, isPaused: false),
                PersistedFocusSession(taskId: UUID(), startedAt: now, secondsRemaining: 180, focusedSeconds: 20, isPaused: true)
            ],
            running: true,
            mode: .standard,
            lastTickAt: now.addingTimeInterval(-90)
        )

        let restored = FocusSessionStore.reconcile(state: state, now: now)
        XCTAssertEqual(restored.sessions[0].secondsRemaining, 210)
        XCTAssertEqual(restored.sessions[0].focusedSeconds, 90)
        XCTAssertEqual(restored.sessions[1].secondsRemaining, 180)
        XCTAssertEqual(restored.sessions[1].focusedSeconds, 20)
        XCTAssertTrue(restored.running)
        XCTAssertFalse(restored.interrupted)
    }

    func testStayOnScreenKillPausesWithoutConsuming() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let state = PersistedFocusState(
            sessions: [
                PersistedFocusSession(taskId: UUID(), startedAt: now, secondsRemaining: 120, focusedSeconds: 10, isPaused: false)
            ],
            running: true,
            mode: .stayOnScreen,
            lastTickAt: now.addingTimeInterval(-40)
        )

        let restored = FocusSessionStore.reconcile(state: state, now: now)
        XCTAssertEqual(restored.sessions[0].secondsRemaining, 120)
        XCTAssertTrue(restored.sessions[0].isPaused)
        XCTAssertFalse(restored.running)
        XCTAssertTrue(restored.interrupted)
    }

    func testPausedCountdownDoesNotConsume() {
        let task = KairosTask(title: "并行", estimatedMinutes: 5)
        var countdown = FocusCountdown(task: task, isPaused: true)
        countdown.consume(90)
        XCTAssertEqual(countdown.secondsRemaining, 300)
        XCTAssertEqual(countdown.focusedSeconds, 0)
    }

    func testSaveAndLoadRoundTrip() {
        let id = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let state = PersistedFocusState(
            sessions: [PersistedFocusSession(taskId: id, startedAt: now, secondsRemaining: 42, focusedSeconds: 8, isPaused: true)],
            running: false,
            mode: .standard,
            lastTickAt: now
        )
        FocusSessionStore.save(state)
        XCTAssertEqual(FocusSessionStore.load(), state)
        FocusSessionStore.clear()
        XCTAssertNil(FocusSessionStore.load())
    }
}
