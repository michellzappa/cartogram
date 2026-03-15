import SwiftUI
import MapCore

@main
struct CartogramApp: App {
    @StateObject private var viewModel = GeneratorViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(viewModel: viewModel)
                .onAppear {
                    SettingsWindowController.shared.configure(viewModel: viewModel)
                    viewModel.resolveLocation()
                }
        } label: {
            Label("Cartogram", systemImage: "map.fill")
        }
    }
}
