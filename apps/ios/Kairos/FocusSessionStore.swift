import Foundation

enum FocusMode: String, Codable {
    case standard
    case stayOnScreen
}

struct PersistedFocusSession: Codable, Equatable {
    var taskId: UUID
    var startedAt: Date
    var secondsRemaining: Int
    var focusedSeconds: Int
    var isPaused: Bool
}

struct PersistedFocusState: Codable, Equatable {
    var sessions: [PersistedFocusSession]
    var running: Bool
    var mode: FocusMode
    var lastTickAt: Date
    var interrupted: Bool = false
}

enum FocusSessionStore {
    static let key = "kairos.persisted.focus.session"

    static func save(_ state: PersistedFocusState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> PersistedFocusState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedFocusState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func reconcile(state: PersistedFocusState, now: Date = .now) -> PersistedFocusState {
        var next = state
        next.interrupted = false
        if state.mode == .standard, state.running {
            let elapsed = max(0, Int(now.timeIntervalSince(state.lastTickAt)))
            next.sessions = state.sessions.map { session in
                var updated = session
                if !updated.isPaused {
                    let amount = min(max(0, elapsed), updated.secondsRemaining)
                    updated.secondsRemaining -= amount
                    updated.focusedSeconds += amount
                }
                return updated
            }
            next.lastTickAt = now
            next.running = next.sessions.contains { !$0.isPaused && $0.secondsRemaining > 0 }
        } else if state.mode == .stayOnScreen, state.running {
            next.sessions = state.sessions.map { session in
                var updated = session
                updated.isPaused = true
                return updated
            }
            next.running = false
            next.interrupted = true
        }
        return next
    }
}
