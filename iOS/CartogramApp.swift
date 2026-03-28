import SwiftUI
import MapCore

@main
struct CartogramApp: App {
    @StateObject private var viewModel = GeneratorViewModel()
    @StateObject private var store = StoreManager.shared
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenWelcome {
                    ContentView(viewModel: viewModel)
                        .environmentObject(store)
                } else {
                    WelcomeView {
                        withAnimation {
                            hasSeenWelcome = true
                        }
                    }
                }
            }
            .task {
                await store.configure()
            }
        }
    }
}
