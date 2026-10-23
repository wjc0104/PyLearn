import SwiftUI

@main
struct PyLearnApp: App {
    @StateObject private var store = LearningStore()
    @StateObject private var session = PythonSession()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(session)
                .tint(.teal)
                .onChange(of: phase) { value in
                    if value != .active { store.flush() }
                    if value == .background && session.running { session.stop() }
                }
        }
    }
}
