import SwiftData
import SwiftUI

@main
struct KairosApp: App {
    private let container: ModelContainer = {
        let schema = Schema([KairosTask.self, Routine.self, ActivityEvent.self, Workstyle.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do { return try ModelContainer(for: schema, configurations: [configuration]) }
        catch { fatalError("Unable to create Kairos data store: \(error)") }
    }()

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(container)
    }
}
