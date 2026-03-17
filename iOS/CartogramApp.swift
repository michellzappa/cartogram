import SwiftUI

@main
struct CartogramApp: App {
    @StateObject private var viewModel = GeneratorViewModel()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                ContentView(viewModel: viewModel)
            } else {
                WelcomeView {
                    withAnimation {
                        hasSeenWelcome = true
                    }
                }
            }
        }
    }
}
