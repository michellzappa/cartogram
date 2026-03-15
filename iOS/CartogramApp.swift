import SwiftUI

@main
struct CartogramApp: App {
    @StateObject private var viewModel = GeneratorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
