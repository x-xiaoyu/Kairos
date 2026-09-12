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
            event.calendar = try kairosCalendar()
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

    private func kairosCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == "Kairos" }) { return existing }
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw CalendarError.noWritableCalendar
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Kairos"
        calendar.source = source
        calendar.cgColor = CGColor(red: 0.19, green: 0.36, blue: 0.29, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}

private enum CalendarError: LocalizedError {
    case noWritableCalendar
    var errorDescription: String? { "No writable Apple Calendar account is available." }
}
