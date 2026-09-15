import SwiftData
import SwiftUI

@main
struct KairosApp: App {
    private let container: ModelContainer = {
        let schema = Schema([KairosTask.self, Routine.self, ActivityEvent.self, Workstyle.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Self.removeStore(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Unable to create Kairos data store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(container)
    }

    private static func removeStore(at url: URL) {
        let extras = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
        for file in extras {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
