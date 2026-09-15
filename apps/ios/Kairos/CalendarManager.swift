import CoreGraphics
import EventKit
import Foundation

@MainActor
final class CalendarManager: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var lastSavedTitle: String?
    private let store = EKEventStore()

    func saveFocusSession(task: KairosTask, startedAt: Date, endedAt: Date, focusedSeconds: Int) async -> Bool {
        guard await ensureAccess() else { return false }
        do {
            let event = EKEvent(eventStore: store)
            event.title = "Kairos · \(task.title)"
            event.startDate = min(startedAt, endedAt)
            event.endDate = max(endedAt, startedAt.addingTimeInterval(60))
            event.notes = "Focused for \(max(1, focusedSeconds / 60)) minute(s). Original estimate: \(task.estimatedMinutes) minutes.\n\nRecorded by Kairos."
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalendarError.noWritableCalendar
            }
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: true)
            lastSavedTitle = event.title
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return true
        case .notDetermined:
            do { return try await store.requestFullAccessToEvents() }
            catch { lastError = error.localizedDescription; return false }
        default:
            lastError = "Calendar access is off. Enable it in Settings → Privacy & Security → Calendars → Kairos."
            return false
        }
    }

}

private enum CalendarError: LocalizedError {
    case noWritableCalendar
    var errorDescription: String? { "No writable Apple Calendar account is available." }
}
